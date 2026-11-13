"""Windows service worker for queued jobs and continuous source watching."""
import logging
import os
import secrets
import threading
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def load_environment():
    env_file = ROOT / '.worker.env'
    if not env_file.is_file():
        raise RuntimeError(f'Missing configuration file: {env_file}')
    allowed = {
        'DATAMOVER_STATE', 'DATAMOVER_ALLOWED_ROOTS', 'DATAMOVER_TZ',
        'DATAMOVER_MAX_WORKERS', 'DATAMOVER_RECONCILE_SECONDS',
    }
    for raw_line in env_file.read_text(encoding='utf-8').splitlines():
        line = raw_line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, value = line.split('=', 1)
        key = key.strip()
        if key not in allowed:
            raise RuntimeError(f'Unsupported setting in .worker.env: {key}')
        os.environ[key] = value.strip()
    os.environ['DATAMOVER_SESSION_SECRET'] = secrets.token_urlsafe(32)


load_environment()

from watchdog.events import FileSystemEventHandler
from watchdog.observers import Observer

from . import main


LOGGER = logging.getLogger('datamover.replication')
POLL_SECONDS = 2
DEBOUNCE_SECONDS = 2
RETRY_SECONDS = 60
RECONCILE_SECONDS = int(os.environ.get('DATAMOVER_RECONCILE_SECONDS', '300'))
if RECONCILE_SECONDS < 60:
    raise RuntimeError('DATAMOVER_RECONCILE_SECONDS must be at least 60')


def set_watcher_status(job_id, status, error=None):
    main.sql(
        '''INSERT INTO worker_watchers(job_id,status,updated,error) VALUES(?,?,?,?)
           ON CONFLICT(job_id) DO UPDATE SET status=excluded.status,
           updated=excluded.updated,error=excluded.error''',
        (job_id, status, main.now(), error),
    )


class ChangeHandler(FileSystemEventHandler):
    def __init__(self, job_id, mark_changed):
        self.job_id = job_id
        self.mark_changed = mark_changed

    def on_any_event(self, event):
        if event.event_type in {'created', 'modified', 'deleted', 'moved'}:
            self.mark_changed(self.job_id)


class ReplicationWorker:
    def __init__(self, stop_event):
        self.stop_event = stop_event
        self.observers = {}
        self.pending = {}
        self.pending_lock = threading.Lock()
        self.next_reconcile = {}
        self.retry_after = {}

    def mark_changed(self, job_id):
        with self.pending_lock:
            self.pending[job_id] = time.monotonic() + DEBOUNCE_SECONDS

    def start_watch(self, job):
        job_id = job['id']
        try:
            source, _ = main.engine.validate_pair(job['source'], job['destination'], main.root_paths())
            if not os.path.isdir(source):
                raise OSError(f'Source folder is unavailable: {source}')
            observer = Observer()
            observer.schedule(ChangeHandler(job_id, self.mark_changed), source, recursive=True)
            observer.start()
        except (OSError, RuntimeError, main.engine.EngineError) as exc:
            self.retry_after[job_id] = time.monotonic() + RETRY_SECONDS
            main.event(job_id, 'error', f'Continuous watcher could not start: {exc}')
            set_watcher_status(job_id, 'error', str(exc)[:500])
            LOGGER.error('Unable to watch Job #%s source: %s', job_id, exc)
            return
        self.observers[job_id] = observer
        set_watcher_status(job_id, 'watching')
        with self.pending_lock:
            self.pending[job_id] = time.monotonic()
        self.next_reconcile[job_id] = time.monotonic() + RECONCILE_SECONDS
        self.retry_after.pop(job_id, None)
        main.event(job_id, 'info', 'Continuous source watcher started; initial reconciliation queued')

    def stop_watch(self, job_id):
        observer = self.observers.pop(job_id, None)
        if observer:
            observer.stop()
            observer.join(timeout=10)
            main.event(job_id, 'info', 'Continuous source watcher stopped')
        set_watcher_status(job_id, 'stopped')
        with self.pending_lock:
            self.pending.pop(job_id, None)
        self.next_reconcile.pop(job_id, None)
        self.retry_after.pop(job_id, None)

    def reconcile_watches(self):
        jobs = main.sql(
            "SELECT * FROM jobs WHERE schedule_type='continuous' AND continuous_ready=1 AND frozen=0 AND handoff=0"
        )
        active = {job['id']: main.decode_job(job) for job in jobs}
        for job_id in set(self.observers) - set(active):
            self.stop_watch(job_id)
        now = time.monotonic()
        for job_id, job in active.items():
            if job_id in self.observers or now < self.retry_after.get(job_id, 0):
                continue
            self.start_watch(job)

    def queue_due_replications(self):
        now = time.monotonic()
        for job_id in list(self.observers):
            job = main.get_job(job_id)
            if job['status'] in ('queued', 'running'):
                continue
            if now >= self.next_reconcile.get(job_id, 0):
                with self.pending_lock:
                    if self.pending.get(job_id, now) > now:
                        self.pending[job_id] = now
            with self.pending_lock:
                due = self.pending.get(job_id, now + 1) <= now
                if due:
                    self.pending.pop(job_id, None)
            if not due:
                continue
            try:
                queued = main.submit(job_id, 'sync', scheduled=True)
            except main.HTTPException as exc:
                main.event(job_id, 'error', f'Continuous reconciliation failed to queue: {exc.detail}')
                LOGGER.error('Unable to queue continuous replication for Job #%s: %s', job_id, exc.detail)
                with self.pending_lock:
                    self.pending.setdefault(job_id, now + RETRY_SECONDS)
                self.next_reconcile[job_id] = now + RETRY_SECONDS
                continue
            if queued:
                self.next_reconcile[job_id] = now + RECONCILE_SECONDS
            else:
                with self.pending_lock:
                    self.pending.setdefault(job_id, now + RETRY_SECONDS)
                self.next_reconcile[job_id] = now + RETRY_SECONDS

    def heartbeat(self):
        main.sql(
            '''INSERT INTO worker_heartbeats(name,updated) VALUES(?,?)
               ON CONFLICT(name) DO UPDATE SET updated=excluded.updated''',
            ('replication', main.now()),
        )

    def run(self):
        while not self.stop_event.is_set():
            self.heartbeat()
            self.reconcile_watches()
            self.queue_due_replications()
            run = main.claim_next_run()
            if run:
                try:
                    main.POOL.submit(main.run_job, run['job_id'], run['mode'], run['id'])
                except RuntimeError as exc:
                    main.sql(
                        "UPDATE runs SET status='failed',finished=?,summary=? WHERE id=?",
                        (main.now(), str(exc)[:500], run['id']),
                    )
                    main.sql(
                        "UPDATE jobs SET status='failed',last_finished=?,last_error=? WHERE id=?",
                        (main.now(), str(exc)[:500], run['job_id']),
                    )
                    with main.LOCK:
                        main.ACTIVE.discard(run['job_id'])
                    main.event(run['job_id'], 'error', f'Worker could not start queued run: {exc}')
            self.stop_event.wait(POLL_SECONDS)

    def stop(self):
        for job_id in list(self.observers):
            self.stop_watch(job_id)


def acquire_service_lock():
    if os.name != 'nt':
        raise RuntimeError('The replication worker service requires Windows')
    import msvcrt

    lock_path = main.STATE / 'replication-worker.lock'
    lock_file = lock_path.open('a+b')
    lock_file.seek(0, os.SEEK_END)
    if lock_file.tell() == 0:
        lock_file.write(b'\0')
        lock_file.flush()
    lock_file.seek(0)
    try:
        msvcrt.locking(lock_file.fileno(), msvcrt.LK_NBLCK, 1)
    except OSError as exc:
        lock_file.close()
        raise RuntimeError('Another replication worker instance is already running') from exc
    return lock_file


def recover_interrupted_runs():
    interrupted = main.sql("SELECT id,job_id FROM runs WHERE status='running'")
    if not interrupted:
        return
    with main.connect() as db:
        for run in interrupted:
            detail = 'Worker stopped before this run completed; review its log before retrying.'
            db.execute(
                "UPDATE runs SET status='failed',finished=?,summary=? WHERE id=? AND status='running'",
                (main.now(), detail, run['id']),
            )
            db.execute(
                "UPDATE jobs SET status='failed',last_finished=?,last_error=? "
                "WHERE id=? AND status='running'",
                (main.now(), detail, run['job_id']),
            )
        db.commit()
    for run in interrupted:
        main.event(run['job_id'], 'error', f'Run #{run["id"]} interrupted by worker shutdown')


def run_worker(stop_event):
    logging.basicConfig(
        filename=main.STATE / 'replication-worker.log',
        level=logging.INFO,
        format='%(asctime)s %(levelname)s %(message)s',
    )
    main.init_db()
    lock_file = acquire_service_lock()
    main.sql(
        "UPDATE worker_watchers SET status='stopped',updated=?,error=NULL",
        (main.now(),),
    )
    worker = ReplicationWorker(stop_event)
    try:
        recover_interrupted_runs()
        worker.run()
    finally:
        worker.stop()
        with main.connect() as db:
            db.execute("DELETE FROM worker_heartbeats WHERE name='replication'")
            db.commit()
        main.POOL.shutdown(wait=True, cancel_futures=False)
        lock_file.close()


if __name__ == '__main__':
    stop_event = threading.Event()
    try:
        run_worker(stop_event)
    except KeyboardInterrupt:
        stop_event.set()
