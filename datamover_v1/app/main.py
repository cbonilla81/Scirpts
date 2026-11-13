"""DataMover v1. Run as a single API process; workers persist jobs in SQLite."""
import json
import os
import re
import secrets
import shutil
import subprocess
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal
from urllib.parse import urlsplit
from zoneinfo import ZoneInfo

from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger
from apscheduler.triggers.date import DateTrigger
from fastapi import FastAPI, Depends, Header, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field, field_validator, model_validator
from sqlalchemy import create_engine, text

BASE = Path(__file__).resolve().parent
STATE = Path(os.environ.get('DATAMOVER_STATE', str(BASE.parent / 'state'))).resolve()
STATE.mkdir(parents=True, exist_ok=True)
DB = create_engine('sqlite:///' + str(STATE / 'jobs.sqlite3'), connect_args={'check_same_thread': False})
API_KEY = os.environ.get('DATAMOVER_API_KEY', '')
if len(API_KEY) < 32:
    raise RuntimeError('Set DATAMOVER_API_KEY to a random secret of at least 32 characters')
ALLOWED = [x.strip() for x in os.environ.get('DATAMOVER_ALLOWED_ROOTS', '').split(';') if x.strip()]
if not ALLOWED:
    raise RuntimeError('Set DATAMOVER_ALLOWED_ROOTS to approved source/destination path prefixes separated by semicolons')
TZ = os.environ.get('DATAMOVER_TZ', 'UTC')
ZoneInfo(TZ)
WORKERS = int(os.environ.get('DATAMOVER_MAX_WORKERS', '2'))
semaphore = threading.BoundedSemaphore(WORKERS)
locks = set()
lock = threading.RLock()
scheduler = BackgroundScheduler(timezone=TZ)
app = FastAPI(title='DataMover Enterprise v1', docs_url=None, redoc_url=None, openapi_url=None)

with DB.begin() as c:
    c.execute(text('''CREATE TABLE IF NOT EXISTS jobs (
        id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, source TEXT NOT NULL,
        destination TEXT NOT NULL, engine TEXT NOT NULL, cron TEXT, status TEXT NOT NULL DEFAULT 'idle',
        phase TEXT NOT NULL DEFAULT 'created', last_exit INTEGER, started TEXT, finished TEXT,
        bytes_done INTEGER DEFAULT 0, files_done INTEGER DEFAULT 0, last_error TEXT,
        created TEXT NOT NULL, cutover_approved INTEGER DEFAULT 0, cutover_note TEXT,
        validated INTEGER DEFAULT 0, source_frozen INTEGER DEFAULT 0, handoff_complete INTEGER DEFAULT 0
    )'''))
    c.execute(text('''CREATE TABLE IF NOT EXISTS events (
        id INTEGER PRIMARY KEY AUTOINCREMENT, job_id INTEGER NOT NULL, ts TEXT NOT NULL,
        level TEXT NOT NULL, message TEXT NOT NULL
    )'''))

# Forward-compatible schema upgrades for existing v1 databases.
with DB.begin() as c:
    cols = {r[1] for r in c.execute(text('PRAGMA table_info(jobs)'))}
    for name, typ in [('dry_run_ok','INTEGER DEFAULT 0'),('dry_run_at','TEXT'),('final_verified','INTEGER DEFAULT 0'),('bytes_total','INTEGER DEFAULT 0'),('progress_pct','REAL DEFAULT 0'),('eta','TEXT')]:
        if name not in cols:
            c.execute(text(f'ALTER TABLE jobs ADD COLUMN {name} {typ}'))
    schedule_columns = [
        ('schedule_type', "TEXT NOT NULL DEFAULT 'manual'"),
        ('scheduled_at', 'TEXT'),
        ('schedule_time', 'TEXT'),
        ('schedule_days', 'TEXT'),
        ('schedule_day', 'INTEGER'),
        ('execution_mode', "TEXT NOT NULL DEFAULT 'async'"),
    ]
    for name, typ in schedule_columns:
        if name not in cols:
            c.execute(text(f'ALTER TABLE jobs ADD COLUMN {name} {typ}'))
    c.execute(text("UPDATE jobs SET schedule_type='cron' WHERE cron IS NOT NULL AND TRIM(cron)!='' AND schedule_type='manual'"))

def now(): return datetime.now(timezone.utc).isoformat()

def auth(x_api_key: str | None = Header(default=None)):
    if not x_api_key or not secrets.compare_digest(x_api_key, API_KEY):
        raise HTTPException(401, 'Invalid API key')

def check_path(path):
    if not path or '\n' in path or '\r' in path or '\x00' in path or path.startswith('-'):
        raise ValueError('Invalid path')
    # rclone remote syntax is remote:bucket/path; local absolute paths are also supported.
    def allowed(p, root):
        p = p.replace('\\', '/').rstrip('/').casefold()
        root = root.replace('\\', '/').rstrip('/').casefold()
        return p == root or p.startswith(root + '/')
    if not any(allowed(path, root) for root in ALLOWED):
        raise ValueError('Path not within DATAMOVER_ALLOWED_ROOTS')
    return path

class JobIn(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    source: str
    destination: str
    engine: Literal['rclone', 'robocopy'] = 'rclone'
    cron: str | None = None
    schedule_type: Literal['manual', 'once', 'daily', 'weekly', 'monthly', 'cron'] = 'manual'
    scheduled_at: datetime | None = None
    schedule_time: str | None = None
    schedule_days: list[Literal['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun']] = Field(default_factory=list)
    schedule_day: int | None = Field(default=None, ge=1, le=31)
    execution_mode: Literal['async', 'sync'] = 'async'
    @field_validator('source', 'destination')
    @classmethod
    def validate_path(cls, v): return check_path(v)
    @field_validator('cron')
    @classmethod
    def validate_cron(cls, v):
        if v:
            parts = v.split()
            if len(parts) != 5: raise ValueError('Cron must have 5 fields')
            CronTrigger.from_crontab(v, timezone=TZ)
        return v
    @field_validator('scheduled_at')
    @classmethod
    def normalize_scheduled_at(cls, v):
        if v is None: return v
        local_tz = ZoneInfo(TZ)
        v = v.replace(tzinfo=local_tz) if v.tzinfo is None else v.astimezone(local_tz)
        if v <= datetime.now(local_tz):
            raise ValueError('Scheduled date and time must be in the future')
        return v
    @field_validator('schedule_time')
    @classmethod
    def validate_schedule_time(cls, v):
        if v is not None:
            try: datetime.strptime(v, '%H:%M')
            except ValueError as exc: raise ValueError('Schedule time must use HH:MM') from exc
        return v
    @model_validator(mode='after')
    def validate_schedule(self):
        if self.cron and self.schedule_type == 'manual':
            self.schedule_type = 'cron'
        if self.schedule_type == 'cron' and not self.cron:
            raise ValueError('Cron schedule requires a cron expression')
        if self.schedule_type == 'once' and not self.scheduled_at:
            raise ValueError('One-time schedule requires a date and time')
        if self.schedule_type in ('daily', 'weekly', 'monthly') and not self.schedule_time:
            raise ValueError('Recurring schedule requires a time')
        if self.schedule_type == 'weekly':
            if not self.schedule_days:
                raise ValueError('Weekly schedule requires at least one day')
            if len(set(self.schedule_days)) != len(self.schedule_days):
                raise ValueError('Weekly schedule days must be unique')
        if self.schedule_type == 'monthly' and self.schedule_day is None:
            raise ValueError('Monthly schedule requires a day of the month')
        return self

class Approval(BaseModel):
    note: str = Field(min_length=8, max_length=500)
    source_frozen: bool
    confirm: Literal['APPROVE FINAL SYNC']

class Handoff(BaseModel):
    confirm: Literal['HANDOFF VERIFIED']
    note: str = Field(min_length=8, max_length=500)

def record(jid, level, message):
    with DB.begin() as c:
        c.execute(text('INSERT INTO events(job_id,ts,level,message) VALUES(:j,:t,:l,:m)'), dict(j=jid,t=now(),l=level,m=message[:1000]))

def update(jid, **values):
    if not values: return
    assignments = ','.join(f'{k}=:{k}' for k in values)
    with DB.begin() as c:
        c.execute(text(f'UPDATE jobs SET {assignments} WHERE id=:id'), {**values, 'id':jid})

def decode_job(row):
    job = dict(row)
    job['schedule_days'] = json.loads(job['schedule_days']) if job.get('schedule_days') else []
    return job

def get_job(jid):
    with DB.connect() as c:
        r = c.execute(text('SELECT * FROM jobs WHERE id=:id'), {'id':jid}).mappings().first()
    if not r: raise HTTPException(404, 'Job not found')
    return decode_job(r)

def command_for(job, verify=False, dry_run=False):
    src, dst = check_path(job['source']), check_path(job['destination'])
    if src.casefold().rstrip('/\\') == dst.casefold().rstrip('/\\'):
        raise ValueError('Source and destination must differ')
    if job['engine'] == 'rclone':
        if verify:
            return ['rclone','check',src,dst,'--one-way','--log-level','INFO']
        cmd = ['rclone','copy',src,dst,'--log-level','INFO','--stats','10s',
               '--stats-one-line','--stats-one-line-date','--transfers',
               os.environ.get('DATAMOVER_TRANSFERS','8'),'--checkers','16','--retries','3']
        if dry_run: cmd.append('--dry-run')
        return cmd
    if os.name != 'nt': raise ValueError('Robocopy requires a Windows worker')
    if verify or dry_run:
        return ['robocopy', src, dst, '/E', '/COPYALL', '/DCOPY:DAT', '/L', '/R:0', '/W:0', '/XJ']
    return ['robocopy', src, dst, '/E', '/COPYALL', '/DCOPY:DAT', '/ZB', '/R:3', '/W:5', '/XJ', '/MT:16', '/NP']

def execute(jid, verify=False, final=False, dry_run=False):
    try:
        job = get_job(jid)
        phase = 'dry_run' if dry_run else ('final_validation' if verify and final else 'final_sync' if final else 'validation' if verify else 'sync')
        update(jid, status='running', phase=phase, started=now(), last_error=None)
        record(jid, 'info', f'{phase} started')
        cmd = command_for(job, verify=verify, dry_run=dry_run)
        if not shutil.which(cmd[0]): raise RuntimeError(f'{cmd[0]} executable not found in PATH')
        logpath = STATE / f'job-{jid}.log'
        with open(logpath, 'a', encoding='utf-8', errors='replace') as logfile:
            logfile.write(f'\n[{now()}] {phase} started\n')
            logfile.flush()
            # Never invoke a shell; credentials belong in rclone config/environment, not command arguments.
            p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors='replace', bufsize=1)
            for line in p.stdout:
                logfile.write(line)
                # Keep only recent progress messages in DB; log file stores full output.
                if 'Transferred:' in line or 'ERROR' in line or 'Failed' in line:
                    record(jid, 'error' if 'ERROR' in line else 'info', line.strip())
                    # Rclone stats are advisory, not an integrity guarantee.
                    m = re.search(r'Transferred:\s*[^,]+,\s*(\d{1,3})%', line)
                    if m and not dry_run and not verify:
                        update(jid, progress_pct=min(100.0,float(m.group(1))))
            rc = p.wait()
        success = rc == 0 if job['engine'] == 'rclone' else rc < 8
        # Robocopy /L return codes indicate differences, not proof of validation.
        if verify and job['engine'] == 'robocopy':
            # Robocopy /L is a differences report; rc=0 alone does not prove ACL equivalence.
            success = rc == 0
        status = 'ready' if success else 'failed'
        result_phase = ('dry_run_complete' if dry_run and success else
                        'final_verified' if final and verify and success else
                        'validated' if verify and success else
                        'final_complete' if final and success else
                        'synced' if success else 'failed')
        vals = dict(status=status, phase=result_phase, last_exit=rc, finished=now())
        if dry_run:
            vals.update(dry_run_ok=int(success), dry_run_at=now() if success else None)
        elif verify and final:
            vals['final_verified'] = int(success)
        elif verify:
            vals['validated'] = int(success)
        elif final:
            vals['final_verified'] = 0
        else:
            vals.update(validated=0, dry_run_ok=0, final_verified=0)
        if success and not dry_run and not verify: vals['progress_pct']=100.0
        update(jid, **vals)
        record(jid, 'info' if success else 'error', f'{phase} finished, exit code {rc}; success={success}')
    except Exception as exc:
        update(jid, status='failed', phase='failed', last_error=str(exc), finished=now())
        record(jid, 'error', f'Execution failed: {exc}')
    finally:
        with lock: locks.discard(jid)
        semaphore.release()

def launch(jid, verify=False, final=False, dry_run=False):
    with lock:
        job = get_job(jid)
        if jid in locks or job['status']=='running': raise HTTPException(409, 'Job already running')
        if not semaphore.acquire(blocking=False):
            raise HTTPException(503, 'All migration workers are busy')
        locks.add(jid)
        try:
            update(jid, status='running', phase='queued')
        except Exception:
            locks.discard(jid)
            semaphore.release()
            raise
    if job['execution_mode'] == 'sync':
        execute(jid, verify, final, dry_run)
        result = get_job(jid)
        return {'queued':False,'status':result['status'],'error':result['last_error']}
    try:
        threading.Thread(target=execute, args=(jid,verify,final,dry_run), daemon=True).start()
    except Exception as exc:
        with lock:
            locks.discard(jid)
            semaphore.release()
        update(jid, status='failed', phase='failed', last_error=str(exc), finished=now())
        record(jid, 'error', f'Could not start worker: {exc}')
        raise HTTPException(500, 'Could not start migration worker') from exc
    return {'queued':True}

def scheduled_run(jid):
    try:
        j=get_job(jid)
        if j['cutover_approved'] or j['handoff_complete']: return
        launch(jid)
    except Exception as e: record(jid, 'warning', f'Scheduled run skipped: {e}')

def schedule_job(job):
    sid=f'job-{job["id"]}'
    if scheduler.get_job(sid): scheduler.remove_job(sid)
    if job['cutover_approved'] or job['handoff_complete']: return
    schedule_type = job.get('schedule_type') or ('cron' if job.get('cron') else 'manual')
    if schedule_type == 'cron' and job.get('cron'):
        trigger = CronTrigger.from_crontab(job['cron'], timezone=TZ)
    elif schedule_type == 'once' and job.get('scheduled_at'):
        run_at = datetime.fromisoformat(job['scheduled_at'])
        if run_at <= datetime.now(ZoneInfo(TZ)): return
        trigger = DateTrigger(run_date=run_at)
    elif schedule_type in ('daily', 'weekly', 'monthly') and job.get('schedule_time'):
        hour, minute = map(int, job['schedule_time'].split(':'))
        fields = {'hour':hour, 'minute':minute, 'timezone':TZ}
        if schedule_type == 'weekly':
            days = job.get('schedule_days') or []
            if isinstance(days, str): days = json.loads(days)
            fields['day_of_week'] = ','.join(days)
        elif schedule_type == 'monthly':
            fields['day'] = job['schedule_day']
        trigger = CronTrigger(**fields)
    else:
        return
    scheduler.add_job(scheduled_run, trigger, args=[job['id']], id=sid, replace_existing=True,
                      max_instances=1, coalesce=True, misfire_grace_time=120)

@app.on_event('startup')
def startup():
    scheduler.start()
    with DB.connect() as c:
        rows=[dict(x) for x in c.execute(text('SELECT * FROM jobs')).mappings()]
    for job in rows:
        if job['status']=='running': update(job['id'],status='interrupted',phase='interrupted')
        schedule_job(job)

@app.on_event('shutdown')
def shutdown(): scheduler.shutdown(wait=False)

@app.get('/RS&H_Logo.png')
def rsandh_logo():
    return FileResponse(BASE.parent / 'RS&H_Logo.png', media_type='image/png')

@app.get('/')
def index(): return FileResponse(BASE / 'static' / 'index.html')
app.mount('/static', StaticFiles(directory=BASE / 'static'), name='static')

@app.get('/api/jobs', dependencies=[Depends(auth)])
def jobs():
    with DB.connect() as c:
        return [decode_job(x) for x in c.execute(text('SELECT * FROM jobs ORDER BY id DESC')).mappings()]

@app.post('/api/jobs', dependencies=[Depends(auth)])
def create(data: JobIn):
    if data.source.casefold().rstrip('/\\') == data.destination.casefold().rstrip('/\\'):
        raise HTTPException(400, 'Source and destination cannot match')
    schedule_days = json.dumps(data.schedule_days) if data.schedule_days else None
    cron = data.cron if data.schedule_type == 'cron' else None
    with DB.begin() as c:
        result=c.execute(text('''INSERT INTO jobs
            (name,source,destination,engine,cron,schedule_type,scheduled_at,schedule_time,schedule_days,schedule_day,execution_mode,created)
            VALUES(:n,:s,:d,:e,:c,:st,:sa,:tm,:sd,:day,:mode,:t)'''),
            dict(n=data.name,s=data.source,d=data.destination,e=data.engine,c=cron,st=data.schedule_type,
                 sa=data.scheduled_at.isoformat() if data.scheduled_at else None,tm=data.schedule_time,
                 sd=schedule_days,day=data.schedule_day,mode=data.execution_mode,t=now()))
        jid=result.lastrowid
    schedule_job(get_job(jid))
    record(jid,'info','Job created')
    return get_job(jid)

@app.get('/api/jobs/{jid}', dependencies=[Depends(auth)])
def detail(jid:int): return get_job(jid)

@app.get('/api/jobs/{jid}/events', dependencies=[Depends(auth)])
def events(jid:int):
    get_job(jid)
    with DB.connect() as c:
        return [dict(x) for x in c.execute(text('SELECT * FROM events WHERE job_id=:id ORDER BY id DESC LIMIT 100'),{'id':jid}).mappings()]

@app.post('/api/jobs/{jid}/dry-run', dependencies=[Depends(auth)])
def dry_run(jid:int):
    j=get_job(jid)
    if j['cutover_approved'] or j['handoff_complete']:
        raise HTTPException(409,'Dry run unavailable after cutover approval')
    result=launch(jid,dry_run=True)
    return {**result,'mode':'non-mutating engine simulation'}

@app.get('/api/jobs/{jid}/rollback-plan', dependencies=[Depends(auth)])
def rollback_plan(jid:int):
    j=get_job(jid)
    return {'job_id':jid,'automatic_rollback':False,'steps':[
        'Keep original source and backups unchanged through the acceptance window',
        'Document existing client mappings and DNS/DFS/share settings before handoff',
        'If handoff fails, freeze destination writes before redirecting clients back',
        'Restore previous client mappings using approved infrastructure change procedures',
        'Reconcile any destination-only writes before resuming production on source',
        'Validate application access, file counts and permissions; record change ticket'],
        'warning':'A rollback plan is advisory and must be tailored to the storage provider.'}

@app.post('/api/jobs/{jid}/sync', dependencies=[Depends(auth)])
def sync(jid:int):
    j=get_job(jid)
    if j['cutover_approved'] or j['handoff_complete']: raise HTTPException(409,'Cutover in progress or complete')
    return launch(jid)

@app.post('/api/jobs/{jid}/validate', dependencies=[Depends(auth)])
def validate(jid:int):
    j=get_job(jid)
    if j['handoff_complete'] or j['cutover_approved']: raise HTTPException(409,'Validation unavailable after cutover approval')
    return launch(jid,verify=True)

@app.post('/api/jobs/{jid}/approve', dependencies=[Depends(auth)])
def approve(jid:int, data:Approval):
    j=get_job(jid)
    if j['status']!='ready' or not j['validated'] or not j['dry_run_ok']:
        raise HTTPException(409,'Successful dry run and validation required before approval')
    if not data.source_frozen: raise HTTPException(400,'Source must be write-frozen and confirmed')
    update(jid,cutover_approved=1,source_frozen=1,cutover_note=data.note,phase='approved')
    schedule_job(get_job(jid))
    record(jid,'warning',f'Operator approved final sync; freeze attested: {data.note}')
    return {'approved':True}

@app.post('/api/jobs/{jid}/final-sync', dependencies=[Depends(auth)])
def final_sync(jid:int):
    j=get_job(jid)
    if not j['cutover_approved'] or not j['source_frozen'] or j['handoff_complete']:
        raise HTTPException(409,'Requires cutover approval and frozen source')
    return launch(jid,final=True)

@app.post('/api/jobs/{jid}/final-validate', dependencies=[Depends(auth)])
def final_validate(jid:int):
    j=get_job(jid)
    if not j['cutover_approved'] or j['phase']!='final_complete' or j['status']!='ready':
        raise HTTPException(409,'Successful final sync required before final verification')
    return launch(jid,verify=True,final=True)

@app.post('/api/jobs/{jid}/handoff', dependencies=[Depends(auth)])
def handoff(jid:int, data:Handoff):
    j=get_job(jid)
    if not j['cutover_approved'] or j['phase']!='final_verified' or not j['final_verified'] or j['status']!='ready':
        raise HTTPException(409,'Successful final sync and final verification required')
    update(jid,handoff_complete=1,phase='handoff_complete',status='complete')
    record(jid,'warning',f'Operator confirmed external share/DNS/DFS handoff: {data.note}')
    return {'complete':True,'note':'Client mapping changes are external/manual in v1'}

@app.get('/api/health', dependencies=[Depends(auth)])
def health(): return {'status':'ok','scheduler':scheduler.running,'active_workers':len(locks),'timezone':TZ}
