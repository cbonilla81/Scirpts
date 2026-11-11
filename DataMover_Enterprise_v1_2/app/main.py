"""DataMover v1.2: single-host Windows pilot. No cloud or remote code execution."""
import hmac
import json
import logging
import os
import re
import secrets
import sqlite3
import subprocess
import threading
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit
from uuid import UUID
from zoneinfo import ZoneInfo
from contextlib import asynccontextmanager
from concurrent.futures import ThreadPoolExecutor

from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger
from authlib.integrations.starlette_client import OAuth, OAuthError
from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.responses import FileResponse, RedirectResponse
from pydantic import BaseModel, Field
from starlette.middleware.sessions import SessionMiddleware
from . import engine
from .authentication import (
    DirectoryUnavailable,
    InvalidCredentials,
    authenticate_ad,
    hash_password,
    verify_password,
)

ROOT = Path(__file__).resolve().parent.parent
STATE = Path(os.environ.get('DATAMOVER_STATE', str(ROOT / 'state')))
STATE.mkdir(parents=True, exist_ok=True)
(STATE / 'logs').mkdir(exist_ok=True)
DBPATH = STATE / 'datamover.sqlite3'
SESSION_SECRET = os.environ.get('DATAMOVER_SESSION_SECRET', '')
if len(SESSION_SECRET) < 32 or SESSION_SECRET.startswith('REPLACE_'):
    raise RuntimeError('DATAMOVER_SESSION_SECRET must be a random secret of at least 32 characters')
COOKIE_SECURE = os.environ.get('DATAMOVER_COOKIE_SECURE', 'false').casefold() == 'true'
ROOTS = [x.strip() for x in os.environ.get('DATAMOVER_ALLOWED_ROOTS', '').split(';') if x.strip()]
if not ROOTS:
    raise RuntimeError('Set DATAMOVER_ALLOWED_ROOTS to semicolon-delimited approved Windows paths')
ROOTS = [engine.normalize_path(x) for x in ROOTS]
AD_LDAP_URL = os.environ.get('DATAMOVER_AD_LDAP_URL', '').strip()
AD_CA_CERT = os.environ.get('DATAMOVER_AD_CA_CERT', '').strip() or None
ENTRA_CLIENT_ID = os.environ.get('DATAMOVER_ENTRA_CLIENT_ID', '').strip()
ENTRA_CLIENT_SECRET = os.environ.get('DATAMOVER_ENTRA_CLIENT_SECRET', '')
ENTRA_REDIRECT_URI = os.environ.get('DATAMOVER_ENTRA_REDIRECT_URI', '').strip()
ENTRA_ALLOWED_TENANTS = {
    item.strip().casefold()
    for item in os.environ.get('DATAMOVER_ENTRA_ALLOWED_TENANTS', '').split(',')
    if item.strip()
}
ENTRA_ENABLED = bool(ENTRA_CLIENT_ID or ENTRA_CLIENT_SECRET or ENTRA_REDIRECT_URI or ENTRA_ALLOWED_TENANTS)
if ENTRA_ENABLED:
    if not (ENTRA_CLIENT_ID and ENTRA_CLIENT_SECRET and ENTRA_REDIRECT_URI and ENTRA_ALLOWED_TENANTS):
        raise RuntimeError('Configure Entra client ID, secret, redirect URI and allowed tenant IDs together')
    try:
        for tenant_id in ENTRA_ALLOWED_TENANTS:
            UUID(tenant_id)
        if urlsplit(ENTRA_REDIRECT_URI).scheme != 'https':
            raise ValueError('Entra redirect URI must use HTTPS')
    except ValueError as exc:
        raise RuntimeError(f'Invalid Entra configuration: {exc}') from exc
SETUP_TOKEN_CONFIG = os.environ.get('DATAMOVER_SETUP_TOKEN', '').strip()
if SETUP_TOKEN_CONFIG and len(SETUP_TOKEN_CONFIG) < 24:
    raise RuntimeError('DATAMOVER_SETUP_TOKEN must contain at least 24 characters')
TZ = os.environ.get('DATAMOVER_TZ', 'UTC')
ZoneInfo(TZ)
POOL = ThreadPoolExecutor(max_workers=max(1, min(8, int(os.environ.get('DATAMOVER_MAX_WORKERS', '2')))))
SCHED = BackgroundScheduler(timezone=TZ)
ACTIVE = set()
LOCK = threading.RLock()
AUTH_FAILURES = {}
SETUP_TOKEN = None
DUMMY_PASSWORD_HASH = None
LOGGER = logging.getLogger('datamover.auth')

def now():
    return datetime.now(timezone.utc).isoformat()

def connect():
    db = sqlite3.connect(DBPATH, timeout=30)
    db.row_factory = sqlite3.Row
    db.execute('PRAGMA busy_timeout=30000')
    db.execute('PRAGMA journal_mode=WAL')
    return db

def sql(query, params=(), *, one=False):
    with connect() as db:
        cur = db.execute(query, params)
        if query.lstrip().upper().startswith('SELECT'):
            rows = [dict(r) for r in cur.fetchall()]
            return (rows[0] if rows else None) if one else rows
        db.commit()
        return cur.lastrowid

def event(job_id, level, message):
    sql('INSERT INTO events(job_id,ts,level,message) VALUES(?,?,?,?)', (job_id, now(), level, str(message)[:1800]))

def init_db():
    with connect() as db:
        db.executescript('''CREATE TABLE IF NOT EXISTS jobs (
        id INTEGER PRIMARY KEY, name TEXT NOT NULL, source TEXT NOT NULL, destination TEXT NOT NULL,
        cron TEXT, threads INTEGER NOT NULL DEFAULT 16, status TEXT NOT NULL DEFAULT 'idle',
        phase TEXT NOT NULL DEFAULT 'created', last_exit INTEGER, last_started TEXT, last_finished TEXT,
        dry_run_ok INTEGER NOT NULL DEFAULT 0, validated INTEGER NOT NULL DEFAULT 0,
        frozen INTEGER NOT NULL DEFAULT 0, approved INTEGER NOT NULL DEFAULT 0,
        final_verified INTEGER NOT NULL DEFAULT 0, handoff INTEGER NOT NULL DEFAULT 0,
        last_error TEXT, created TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS events (id INTEGER PRIMARY KEY, job_id INTEGER, ts TEXT, level TEXT, message TEXT);
        CREATE TABLE IF NOT EXISTS runs (id INTEGER PRIMARY KEY, job_id INTEGER, mode TEXT, started TEXT,
        finished TEXT, status TEXT, exit_code INTEGER, log_file TEXT, summary TEXT);
        CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY, username TEXT NOT NULL COLLATE NOCASE UNIQUE,
        password_hash TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 1,
        is_admin INTEGER NOT NULL DEFAULT 0, created TEXT NOT NULL);
        ''')

def get_job(jid):
    job = sql('SELECT * FROM jobs WHERE id=?', (jid,), one=True)
    if not job:
        raise HTTPException(404, 'Job not found')
    return job

def schedule(job):
    SCHED.remove_job(str(job['id'])) if SCHED.get_job(str(job['id'])) else None
    if job['cron'] and not job['handoff']:
        SCHED.add_job(lambda jid=job['id']: submit(jid, 'sync', scheduled=True),
                      CronTrigger.from_crontab(job['cron'], timezone=TZ), id=str(job['id']),
                      replace_existing=True, coalesce=True, max_instances=1, misfire_grace_time=120)

def invalidate(jid):
    sql('UPDATE jobs SET dry_run_ok=0, validated=0, frozen=0, approved=0, final_verified=0 WHERE id=?', (jid,))

def submit(jid, mode, scheduled=False):
    job = get_job(jid)
    with LOCK:
        if jid in ACTIVE:
            if scheduled:
                event(jid, 'warning', 'Scheduled run skipped: job already running')
                return False
            raise HTTPException(409, 'Job already running')
        if job['handoff']:
            raise HTTPException(409, 'Job has been handed off')
        if mode == 'final' and not (job['dry_run_ok'] and job['validated'] and job['frozen'] and job['approved']):
            raise HTTPException(409, 'Final sync requires dry run, validation, freeze confirmation and approval')
        if mode == 'sync' and job['frozen']:
            raise HTTPException(409, 'Source is marked frozen; use final sync')
        ACTIVE.add(jid)
        sql('UPDATE jobs SET status=?,phase=?,last_started=?,last_error=NULL WHERE id=?',
            ('running', mode, now(), jid))
        try:
            POOL.submit(run_job, jid, mode)
        except Exception:
            ACTIVE.discard(jid)
            raise
    return True

def run_job(jid, mode):
    log_path = None
    run_id = None
    try:
        job = get_job(jid)
        stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
        log_path = STATE / 'logs' / f'job-{jid}-{mode}-{stamp}.log'
        args = engine.command(job['source'], job['destination'], dry_run=(mode == 'dry-run'),
                              final=(mode == 'final'), threads=job['threads'], log_path=log_path)
        run_id = sql('INSERT INTO runs(job_id,mode,started,status,log_file) VALUES(?,?,?,?,?)',
                     (jid, mode, now(), 'running', str(log_path)))
        event(jid, 'info', f'{mode} started (run #{run_id})')
        # No shell, no user-controlled switches. Output goes to a bounded in-memory tail.
        proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, errors='replace', creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        tail = []
        for line in proc.stdout:
            line = line.rstrip()
            if line:
                tail.append(line[-500:])
                if len(tail) > 30:
                    tail.pop(0)
        code = proc.wait()
        ok = engine.exit_success(code)
        status = 'success' if ok else 'failed'
        summary = '\n'.join(tail[-15:])[-5000:]
        sql('UPDATE runs SET finished=?,status=?,exit_code=?,summary=? WHERE id=?',
            (now(), status, code, summary, run_id))
        sql('UPDATE jobs SET status=?,phase=?,last_exit=?,last_finished=?,last_error=? WHERE id=?',
            (status, mode, code, now(), None if ok else f'Robocopy exit code {code}', jid))
        if ok:
            if mode == 'dry-run':
                sql('UPDATE jobs SET dry_run_ok=1 WHERE id=?', (jid,))
            elif mode == 'sync':
                invalidate(jid)
            elif mode == 'final':
                sql('UPDATE jobs SET final_verified=0 WHERE id=?', (jid,))
        else:
            if mode in ('dry-run', 'final'):
                invalidate(jid)
        event(jid, 'info' if ok else 'error', f'{mode} {status}; Robocopy exit={code}. See run log.')
    except Exception as exc:
        sql('UPDATE jobs SET status=?,last_finished=?,last_error=? WHERE id=?', ('failed', now(), str(exc)[:500], jid))
        if run_id:
            sql('UPDATE runs SET finished=?,status=?,summary=? WHERE id=?', (now(), 'failed', str(exc)[:500], run_id))
        event(jid, 'error', f'{mode} failed: {exc}')
    finally:
        with LOCK:
            ACTIVE.discard(jid)

def setup_required():
    return sql('SELECT COUNT(*) AS count FROM users', one=True)['count'] == 0

def start_session(request, identity):
    request.session.clear()
    csrf_token = secrets.token_urlsafe(32)
    request.session['identity'] = identity
    request.session['csrf_token'] = csrf_token
    return {'user': identity, 'csrf_token': csrf_token}

def require_auth(request: Request):
    identity = request.session.get('identity')
    if not isinstance(identity, dict):
        raise HTTPException(401, 'Sign-in required')
    if identity.get('provider') == 'local':
        user = sql('SELECT id,username,enabled,is_admin FROM users WHERE id=?',
                   (identity.get('id'),), one=True)
        if not user or not user['enabled']:
            request.session.clear()
            raise HTTPException(401, 'Account is disabled or no longer exists')
        identity = {
            'id': user['id'], 'username': user['username'], 'provider': 'local',
            'is_admin': bool(user['is_admin']),
        }
        request.session['identity'] = identity
    request.state.auth_user = identity
    return identity

def require_admin(user=Depends(require_auth)):
    if not user.get('is_admin'):
        raise HTTPException(403, 'Local administrator access required')
    return user

def require_csrf(request: Request, x_csrf_token: str | None = Header(default=None)):
    expected = request.session.get('csrf_token')
    if not expected or not x_csrf_token or not hmac.compare_digest(expected, x_csrf_token):
        raise HTTPException(403, 'Invalid or missing CSRF token')

def require_same_origin(request: Request):
    origin = request.headers.get('origin')
    host = request.headers.get('host')
    if origin and host and urlsplit(origin).netloc.casefold() != host.casefold():
        raise HTTPException(403, 'Cross-origin sign-in requests are not allowed')

def check_login_rate(request: Request):
    address = request.client.host if request.client else 'unknown'
    cutoff = datetime.now().timestamp() - 600
    with LOCK:
        attempts = [stamp for stamp in AUTH_FAILURES.get(address, []) if stamp >= cutoff]
        AUTH_FAILURES[address] = attempts
    if len(attempts) >= 10:
        raise HTTPException(429, 'Too many sign-in attempts. Try again in ten minutes.')
    return address

def record_login_failure(address: str):
    with LOCK:
        AUTH_FAILURES.setdefault(address, []).append(datetime.now().timestamp())

def clear_login_failures(address: str):
    with LOCK:
        AUTH_FAILURES.pop(address, None)

def dummy_password_hash():
    global DUMMY_PASSWORD_HASH
    if DUMMY_PASSWORD_HASH is None:
        DUMMY_PASSWORD_HASH = hash_password(secrets.token_urlsafe(24))
    return DUMMY_PASSWORD_HASH

class JobIn(BaseModel):
    name: str = Field(min_length=3, max_length=100)
    source: str
    destination: str
    cron: str | None = None
    threads: int = Field(default=16, ge=1, le=32)

class Note(BaseModel):
    note: str = Field(min_length=12, max_length=1000)

class Confirmation(Note):
    confirmed: bool

class Credentials(BaseModel):
    username: str = Field(min_length=1, max_length=256)
    password: str = Field(min_length=1, max_length=1024)

class FirstAdmin(Credentials):
    setup_code: str = Field(min_length=24, max_length=256)
    username: str = Field(min_length=1, max_length=120, pattern=r'^[A-Za-z0-9._@+-]+$')
    password: str = Field(min_length=12, max_length=1024)

class LocalUserIn(BaseModel):
    username: str = Field(min_length=1, max_length=120, pattern=r'^[A-Za-z0-9._@+-]+$')
    password: str = Field(min_length=12, max_length=1024)
    is_admin: bool = False

class LocalUserStatus(BaseModel):
    enabled: bool

@asynccontextmanager
async def lifespan(app):
    init_db()
    global SETUP_TOKEN
    if setup_required():
        SETUP_TOKEN = SETUP_TOKEN_CONFIG or secrets.token_urlsafe(32)
        if not SETUP_TOKEN_CONFIG:
            LOGGER.warning('First administrator setup is required. One-time setup code: %s', SETUP_TOKEN)
    else:
        SETUP_TOKEN = None
    for job in sql('SELECT * FROM jobs'):
        schedule(job)
    SCHED.start()
    yield
    SCHED.shutdown(wait=False)
    POOL.shutdown(wait=False, cancel_futures=True)

app = FastAPI(title='DataMover Enterprise v1.2', docs_url=None, redoc_url=None,
              openapi_url=None, lifespan=lifespan)
app.add_middleware(
    SessionMiddleware,
    secret_key=SESSION_SECRET,
    session_cookie='datamover_session',
    max_age=8 * 60 * 60,
    same_site='lax',
    https_only=COOKIE_SECURE,
)
oauth = OAuth()
if ENTRA_ENABLED:
    oauth.register(
        name='entra',
        client_id=ENTRA_CLIENT_ID,
        client_secret=ENTRA_CLIENT_SECRET,
        server_metadata_url='https://login.microsoftonline.com/organizations/v2.0/.well-known/openid-configuration',
        client_kwargs={'scope': 'openid profile email'},
    )

@app.get('/')
def homepage():
    return FileResponse(ROOT / 'app' / 'static' / 'index.html')

@app.get('/login')
def login_page():
    return FileResponse(ROOT / 'app' / 'static' / 'index.html')

@app.get('/RS&H_Logo.png')
def rsandh_logo():
    return FileResponse(ROOT / 'RS&H_Logo.png', media_type='image/png')

@app.get('/demo')
def demo_page():
    return FileResponse(ROOT / 'app' / 'static' / 'demo.html')

@app.get('/api/auth/methods')
def auth_methods():
    return {
        'local': True,
        'ad': bool(AD_LDAP_URL),
        'entra': ENTRA_ENABLED,
        'setup_required': setup_required(),
    }

@app.get('/api/auth/session')
def auth_session(request: Request, user=Depends(require_auth)):
    return {'user': user, 'csrf_token': request.session['csrf_token']}

@app.post('/api/auth/setup', dependencies=[Depends(require_same_origin)])
def setup_first_admin(data: FirstAdmin, request: Request):
    global SETUP_TOKEN
    address = check_login_rate(request)
    with LOCK:
        if not setup_required() or not SETUP_TOKEN:
            raise HTTPException(409, 'Initial administrator setup is already complete')
        if not hmac.compare_digest(data.setup_code, SETUP_TOKEN):
            record_login_failure(address)
            raise HTTPException(401, 'Invalid one-time setup code')
        try:
            user_id = sql(
                'INSERT INTO users(username,password_hash,enabled,is_admin,created) VALUES(?,?,?,?,?)',
                (data.username.strip(), hash_password(data.password), 1, 1, now()),
            )
        except sqlite3.IntegrityError as exc:
            raise HTTPException(409, 'That username is already registered') from exc
        SETUP_TOKEN = None
    clear_login_failures(address)
    identity = {'id': user_id, 'username': data.username.strip(), 'provider': 'local', 'is_admin': True}
    return start_session(request, identity)

@app.post('/api/auth/local', dependencies=[Depends(require_same_origin)])
def local_login(data: Credentials, request: Request):
    if setup_required():
        raise HTTPException(409, 'Create the initial administrator before signing in')
    address = check_login_rate(request)
    username = data.username.strip()
    user = sql('SELECT id,username,password_hash,enabled,is_admin FROM users WHERE username=?',
               (username,), one=True)
    valid = verify_password(data.password, user['password_hash'] if user else dummy_password_hash())
    if not user or not user['enabled'] or not valid:
        record_login_failure(address)
        raise HTTPException(401, 'Invalid username or password')
    clear_login_failures(address)
    identity = {
        'id': user['id'], 'username': user['username'], 'provider': 'local',
        'is_admin': bool(user['is_admin']),
    }
    return start_session(request, identity)

@app.post('/api/auth/ad', dependencies=[Depends(require_same_origin)])
def ad_login(data: Credentials, request: Request):
    if not AD_LDAP_URL:
        raise HTTPException(503, 'Active Directory sign-in is not configured')
    address = check_login_rate(request)
    try:
        authenticate_ad(data.username.strip(), data.password, AD_LDAP_URL, AD_CA_CERT)
    except InvalidCredentials as exc:
        record_login_failure(address)
        raise HTTPException(401, 'Invalid username or password') from exc
    except DirectoryUnavailable as exc:
        raise HTTPException(503, str(exc)) from exc
    clear_login_failures(address)
    username = data.username.strip()
    identity = {
        'id': username.casefold(), 'username': username, 'provider': 'ad', 'is_admin': False,
    }
    return start_session(request, identity)

@app.get('/auth/entra/login')
async def entra_login(request: Request):
    if not ENTRA_ENABLED:
        raise HTTPException(503, 'Microsoft Entra ID sign-in is not configured')
    client = oauth.create_client('entra')
    if client is None:
        raise HTTPException(503, 'Microsoft Entra ID sign-in is not configured')
    return await client.authorize_redirect(
        request, redirect_uri=ENTRA_REDIRECT_URI, code_challenge_method='S256'
    )

@app.get('/auth/entra/callback')
async def entra_callback(request: Request):
    if not ENTRA_ENABLED:
        raise HTTPException(503, 'Microsoft Entra ID sign-in is not configured')
    client = oauth.create_client('entra')
    if client is None:
        raise HTTPException(503, 'Microsoft Entra ID sign-in is not configured')
    try:
        token = await client.authorize_access_token(request)
    except OAuthError as exc:
        LOGGER.warning('Entra sign-in failed: %s', exc.error)
        raise HTTPException(401, 'Microsoft Entra ID sign-in failed') from exc
    claims = token.get('userinfo')
    if not claims:
        raise HTTPException(401, 'Entra ID token did not provide verified user claims')
    tenant_id = str(claims.get('tid', '')).casefold()
    issuer = str(claims.get('iss', '')).rstrip('/').casefold()
    expected_issuer = f'https://login.microsoftonline.com/{tenant_id}/v2.0'
    if tenant_id not in ENTRA_ALLOWED_TENANTS or issuer != expected_issuer:
        request.session.clear()
        raise HTTPException(403, 'Your Entra tenant is not approved for this DataMover instance')
    subject = str(claims.get('oid') or claims.get('sub') or '')
    username = str(claims.get('preferred_username') or claims.get('email') or '')
    if not subject or not username:
        raise HTTPException(401, 'Entra sign-in did not provide a usable user identity')
    start_session(request, {
        'id': f'{tenant_id}:{subject}', 'username': username,
        'provider': 'entra', 'is_admin': False,
    })
    return RedirectResponse('/', status_code=303)

@app.post('/api/auth/logout', dependencies=[Depends(require_auth), Depends(require_csrf)])
def logout(request: Request):
    request.session.clear()
    return {'signed_out': True}

@app.get('/api/users', dependencies=[Depends(require_admin)])
def local_users():
    return sql('SELECT id,username,enabled,is_admin,created FROM users ORDER BY username')

@app.post('/api/users', dependencies=[Depends(require_admin), Depends(require_csrf)], status_code=201)
def create_local_user(data: LocalUserIn):
    try:
        user_id = sql(
            'INSERT INTO users(username,password_hash,enabled,is_admin,created) VALUES(?,?,?,?,?)',
            (data.username.strip(), hash_password(data.password), 1, int(data.is_admin), now()),
        )
    except sqlite3.IntegrityError as exc:
        raise HTTPException(409, 'That username is already registered') from exc
    return sql('SELECT id,username,enabled,is_admin,created FROM users WHERE id=?', (user_id,), one=True)

@app.patch('/api/users/{user_id}', dependencies=[Depends(require_admin), Depends(require_csrf)])
def set_local_user_status(user_id: int, data: LocalUserStatus, user=Depends(require_admin)):
    with LOCK:
        target = sql('SELECT id,is_admin,enabled FROM users WHERE id=?', (user_id,), one=True)
        if not target:
            raise HTTPException(404, 'Local user not found')
        if not data.enabled and user_id == user.get('id'):
            raise HTTPException(409, 'You cannot disable your own account')
        if not data.enabled and target['is_admin']:
            admins = sql('SELECT COUNT(*) AS count FROM users WHERE enabled=1 AND is_admin=1', one=True)['count']
            if admins <= 1:
                raise HTTPException(409, 'The last enabled administrator cannot be disabled')
        sql('UPDATE users SET enabled=? WHERE id=?', (int(data.enabled), user_id))
    return {'updated': True}

@app.get('/api/health', dependencies=[Depends(require_auth)])
def health():
    try:
        exe = engine.executable()
    except engine.EngineError as exc:
        exe = str(exc)
    return {'service': 'ok', 'engine': exe, 'platform': os.name, 'jobs_running': len(ACTIVE)}

@app.get('/api/jobs', dependencies=[Depends(require_auth)])
def jobs():
    return sql('SELECT * FROM jobs ORDER BY id DESC')

@app.post('/api/jobs', dependencies=[Depends(require_auth), Depends(require_csrf)], status_code=201)
def create_job(data: JobIn):
    try:
        src, dst = engine.validate_pair(data.source, data.destination, ROOTS)
        if data.cron:
            CronTrigger.from_crontab(data.cron, timezone=TZ)
    except (engine.EngineError, ValueError) as exc:
        raise HTTPException(422, str(exc))
    jid = sql('INSERT INTO jobs(name,source,destination,cron,threads,created) VALUES(?,?,?,?,?,?)',
              (data.name, src, dst, data.cron, data.threads, now()))
    schedule(get_job(jid))
    event(jid, 'info', 'Job created')
    return get_job(jid)

@app.get('/api/jobs/{jid}', dependencies=[Depends(require_auth)])
def job_detail(jid: int):
    return get_job(jid)

@app.get('/api/jobs/{jid}/events', dependencies=[Depends(require_auth)])
def events(jid: int):
    get_job(jid)
    return sql('SELECT * FROM events WHERE job_id=? ORDER BY id DESC LIMIT 100', (jid,))

@app.get('/api/jobs/{jid}/runs', dependencies=[Depends(require_auth)])
def runs(jid: int):
    get_job(jid)
    return sql('SELECT * FROM runs WHERE job_id=? ORDER BY id DESC LIMIT 50', (jid,))

@app.post('/api/jobs/{jid}/run/{mode}', dependencies=[Depends(require_auth), Depends(require_csrf)])
def run(jid: int, mode: str):
    if mode not in ('dry-run', 'sync', 'final'):
        raise HTTPException(422, 'Unsupported mode')
    submit(jid, mode)
    return {'accepted': True, 'mode': mode}

@app.post('/api/jobs/{jid}/validate', dependencies=[Depends(require_auth), Depends(require_csrf)])
def validate(jid: int, data: Confirmation):
    job = get_job(jid)
    if jid in ACTIVE or not job['dry_run_ok'] or not data.confirmed:
        raise HTTPException(409, 'Complete a successful dry-run and explicitly confirm external ACL/data checks')
    sql('UPDATE jobs SET validated=1 WHERE id=?', (jid,))
    event(jid, 'warning', 'Operator attested validation: ' + data.note)
    return {'validated': True, 'note': 'Manual attestation; not an automated integrity check'}

@app.post('/api/jobs/{jid}/freeze', dependencies=[Depends(require_auth), Depends(require_csrf)])
def freeze(jid: int, data: Confirmation):
    job = get_job(jid)
    if jid in ACTIVE or not job['validated'] or not data.confirmed:
        raise HTTPException(409, 'Validation and explicit source-write-freeze confirmation required')
    sql('UPDATE jobs SET frozen=1 WHERE id=?', (jid,))
    event(jid, 'warning', 'Operator confirmed source writes frozen: ' + data.note)
    return {'frozen': True}

@app.post('/api/jobs/{jid}/approve', dependencies=[Depends(require_auth), Depends(require_csrf)])
def approve(jid: int, data: Confirmation):
    job = get_job(jid)
    if not (job['validated'] and job['frozen'] and data.confirmed):
        raise HTTPException(409, 'Validation, freeze, and approval confirmation required')
    sql('UPDATE jobs SET approved=1 WHERE id=?', (jid,))
    event(jid, 'warning', 'Operator approved final sync: ' + data.note)
    return {'approved': True}

@app.post('/api/jobs/{jid}/verify-final', dependencies=[Depends(require_auth), Depends(require_csrf)])
def verify_final(jid: int, data: Confirmation):
    job = get_job(jid)
    last = sql('SELECT * FROM runs WHERE job_id=? AND mode=? ORDER BY id DESC LIMIT 1', (jid, 'final'), one=True)
    if jid in ACTIVE or not last or last['status'] != 'success' or not data.confirmed:
        raise HTTPException(409, 'Successful final sync and explicit independent verification required')
    sql('UPDATE jobs SET final_verified=1 WHERE id=?', (jid,))
    event(jid, 'warning', 'Operator attested independent final verification: ' + data.note)
    return {'final_verified': True}

@app.post('/api/jobs/{jid}/handoff', dependencies=[Depends(require_auth), Depends(require_csrf)])
def handoff(jid: int, data: Confirmation):
    job = get_job(jid)
    if jid in ACTIVE or not job['final_verified'] or not data.confirmed:
        raise HTTPException(409, 'Independent final verification and handoff confirmation required')
    sql('UPDATE jobs SET handoff=1,status=? WHERE id=?', ('handed-off', jid))
    schedule(get_job(jid))
    event(jid, 'warning', 'Operator confirmed external DFS/DNS/share handoff: ' + data.note)
    return {'handoff': True}

@app.get('/api/jobs/{jid}/rollback-plan', dependencies=[Depends(require_auth)])
def rollback(jid: int):
    job = get_job(jid)
    return {'job': jid, 'warning': 'Planning only; no automated rollback or reverse copy',
            'steps': [f'Retain original source {job["source"]} and document access paths',
                      'Document original DFS targets, share mappings and DNS before handoff',
                      'If rollback needed, stop destination writes and coordinate application owners',
                      'Assess destination-only writes; never reverse-sync blindly',
                      'Restore original client access paths after change approval',
                      'Validate user access and permissions, then document outcome']}
