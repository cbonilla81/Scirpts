import os
import time

import pytest
from fastapi.testclient import TestClient
import threading
from datetime import datetime, timedelta
from types import SimpleNamespace
from fastapi import HTTPException
from pydantic import ValidationError

@pytest.fixture
def roots_db(tmp_path, monkeypatch):
    monkeypatch.setenv('DATAMOVER_STATE', str(tmp_path / 'state'))
    monkeypatch.setenv('DATAMOVER_SESSION_SECRET', 'test-session-secret-for-approved-roots')
    monkeypatch.setenv('DATAMOVER_ALLOWED_ROOTS', r'\\FS01\Shares;\\FS02\Shares')
    from app import main

    monkeypatch.setattr(main, 'DBPATH', tmp_path / 'datamover.sqlite3')
    monkeypatch.setattr(main, 'INITIAL_ROOTS', [r'\\FS01\Shares', r'\\FS02\Shares'])
    main.init_db()
    return main


def test_login_expires_even_after_authenticated_requests(roots_db, monkeypatch):
    main = roots_db
    monkeypatch.setattr(main, 'SESSION_TIMEOUT_MINUTES', 1)
    monkeypatch.setattr(main, 'time', SimpleNamespace(time=lambda: 1000))
    request = SimpleNamespace(session={}, state=SimpleNamespace())
    identity = {'id': 'operator', 'provider': 'ad'}

    main.start_session(request, identity)
    monkeypatch.setattr(main.time, 'time', lambda: 1059)
    assert main.require_auth(request) == identity

    monkeypatch.setattr(main.time, 'time', lambda: 1060)
    with pytest.raises(HTTPException) as expired:
        main.require_auth(request)
    assert expired.value.status_code == 401
    assert request.session == {}


def test_roots_are_seeded_and_can_be_added_and_removed(roots_db):
    main = roots_db
    assert [root['path'] for root in main.get_approved_roots()] == [
        r'\\FS01\Shares', r'\\FS02\Shares'
    ]

    root = r'\\files.example.com\Departments'
    main.add_approved_root(main.ApprovedRootIn(path=root), {'username': 'operator'})
    assert root in main.root_paths()

    main.remove_approved_root(main.ApprovedRootIn(path=root), {'username': 'operator'})
    assert root not in main.root_paths()


def test_removing_last_root_is_rejected(roots_db):
    main = roots_db
    main.remove_approved_root(
        main.ApprovedRootIn(path=r'\\FS01\Shares'), {'username': 'operator'}
    )

    with pytest.raises(HTTPException) as error:
        main.remove_approved_root(
            main.ApprovedRootIn(path=r'\\FS02\Shares'), {'username': 'operator'}
        )
    assert error.value.status_code == 409


def test_smb_credentials_require_admin_and_never_return_password(roots_db, monkeypatch, tmp_path):
    main = roots_db
    path = tmp_path / 'smb.json'
    path.write_text('[]', encoding='utf-8')
    monkeypatch.setattr(main, 'SMB_CREDENTIALS_PATH', str(path))
    monkeypatch.setattr(main, 'COOKIE_SECURE', True)
    monkeypatch.setattr(main, 'os', SimpleNamespace(name='nt'))
    monkeypatch.setattr(main.smb_credentials, 'protect_password', lambda _: b'encrypted')
    user = {'username': 'admin', 'is_admin': False}
    monkeypatch.setitem(main.app.dependency_overrides, main.require_auth, lambda: user)
    monkeypatch.setitem(main.app.dependency_overrides, main.require_csrf, lambda: None)
    payload = {'share': r'\\FS01\Shares', 'username': r'DOMAIN\reader', 'password': 'test-secret'}
    with TestClient(main.app, base_url='https://testserver') as client:
        assert client.put('/api/smb-credentials', json=payload).status_code == 403
        user['is_admin'] = True
        assert client.put('/api/smb-credentials', json={**payload, 'share': r'\\other\share'}).status_code == 409
        response = client.put('/api/smb-credentials', json=payload)
        assert response.status_code == 200
        metadata = {key: payload[key] for key in ('share', 'username')}
        assert response.json() == metadata
        assert client.get('/api/smb-credentials').json() == [metadata]
        assert 'test-secret' not in path.read_text(encoding='utf-8')
        assert client.get('/api/roots').json()[0]['smb_auth'] == 'configured'
        assert client.delete('/api/smb-credentials', params={}).status_code == 415
        assert client.request('DELETE', '/api/smb-credentials', json={'share': payload['share']}).status_code == 200
        assert client.get('/api/roots').json()[0]['smb_auth'] == 'service_account'


def test_removing_root_blocks_saved_job_from_running(roots_db):
    main = roots_db
    job = main.create_job(main.JobIn(
        name='Example migration',
        source=r'\\FS01\Shares\Finance',
        destination=r'\\FS02\Shares\Finance',
    ))
    main.remove_approved_root(
        main.ApprovedRootIn(path=r'\\FS01\Shares'), {'username': 'operator'}
    )

    with pytest.raises(HTTPException) as error:
        main.submit(job['id'], 'sync')
    assert error.value.status_code == 409


@pytest.mark.parametrize(('schedule_type', 'fields'), [
    ('daily', {'schedule_time': '02:30'}),
    ('weekly', {'schedule_time': '02:30', 'schedule_days': ['mon', 'fri']}),
    ('monthly', {'schedule_time': '02:30', 'schedule_day': 31}),
])
def test_recurring_schedule_options_are_persisted(roots_db, schedule_type, fields):
    main = roots_db
    job = main.create_job(main.JobIn(
        name='Weekly migration',
        source=r'\\FS01\Shares\Finance',
        destination=r'\\FS02\Shares\Finance',
        schedule_type=schedule_type,
        execution_mode='sync',
        **fields,
    ))

    assert job['schedule_type'] == schedule_type
    assert job['schedule_time'] == '02:30'
    if schedule_type == 'weekly':
        assert job['schedule_days'] == ['mon', 'fri']
    if schedule_type == 'monthly':
        assert job['schedule_day'] == 31
    assert job['execution_mode'] == 'sync'
    assert main.SCHED.get_job(str(job['id'])) is not None


def test_one_time_job_requires_a_future_datetime(roots_db):
    main = roots_db
    with pytest.raises(ValidationError):
        main.JobIn(
            name='Invalid one-time migration',
            source=r'\\FS01\Shares\Finance',
            destination=r'\\FS02\Shares\Finance',
            schedule_type='once',
        )

    scheduled_at = datetime.now(main.ZoneInfo(main.TZ)) + timedelta(days=1)
    job = main.create_job(main.JobIn(
        name='One-time migration',
        source=r'\\FS01\Shares\Finance',
        destination=r'\\FS02\Shares\Finance',
        schedule_type='once',
        scheduled_at=scheduled_at,
    ))
    assert job['schedule_type'] == 'once'
    assert job['scheduled_at']
    assert main.SCHED.get_job(str(job['id'])) is not None


def test_legacy_cron_schedule_remains_supported(roots_db):
    main = roots_db
    job = main.create_job(main.JobIn(
        name='Legacy cron migration',
        source=r'\\FS01\Shares\Finance',
        destination=r'\\FS02\Shares\Finance',
        cron='0 2 * * *',
    ))

    assert job['schedule_type'] == 'cron'
    assert job['cron'] == '0 2 * * *'
    assert main.SCHED.get_job(str(job['id'])) is not None


def test_continuous_job_uses_worker_and_requires_background_mode(roots_db):
    main = roots_db
    job = main.create_job(main.JobIn(
        name='Continuous migration',
        source=r'\\FS01\Shares\Finance',
        destination=r'\\FS02\Shares\Finance',
        schedule_type='continuous',
    ))

    assert job['schedule_type'] == 'continuous'
    assert job['execution_mode'] == 'async'
    assert main.SCHED.get_job(str(job['id'])) is None
    with pytest.raises(ValidationError):
        main.JobIn(
            name='Invalid continuous migration',
            source=r'\\FS01\Shares\Finance',
            destination=r'\\FS02\Shares\Finance',
            schedule_type='continuous',
            execution_mode='sync',
        )


def test_continuous_replication_starts_only_after_dry_run_and_successful_initial_sync(
    roots_db, monkeypatch
):
    main = roots_db
    job = main.create_job(main.JobIn(
        name='Continuous migration',
        source=r'\\FS01\Shares\Finance',
        destination=r'\\FS02\Shares\Finance',
        schedule_type='continuous',
    ))

    with pytest.raises(HTTPException) as error:
        main.submit(job['id'], 'sync')
    assert error.value.status_code == 409

    main.sql('UPDATE jobs SET dry_run_ok=1 WHERE id=?', (job['id'],))
    run_id = main.sql(
        'INSERT INTO runs(job_id,mode,started,status) VALUES(?,?,?,?)',
        (job['id'], 'sync', main.now(), 'running'),
    )

    class Process:
        stdout = ['Robocopy completed\n']

        def wait(self):
            return 0

    monkeypatch.setattr(main.engine, 'command', lambda *args, **kwargs: ['robocopy.exe'])
    monkeypatch.setattr(main.subprocess, 'Popen', lambda *args, **kwargs: Process())
    main.run_job(job['id'], 'sync', run_id)

    updated = main.get_job(job['id'])
    assert updated['continuous_ready'] == 1
    assert updated['dry_run_ok'] == 1

    main.sql('UPDATE jobs SET dry_run_ok=0 WHERE id=?', (job['id'],))
    main.sql(
        'INSERT INTO worker_heartbeats(name,updated) VALUES(?,?)',
        ('replication', main.now()),
    )
    main.sql(
        'INSERT INTO worker_watchers(job_id,status,updated) VALUES(?,?,?)',
        (job['id'], 'watching', main.now()),
    )
    assert main.continuous_job_status(True)[0]['state'] == 'watching'


@pytest.mark.parametrize(('code', 'levels'), [(0, []), (1, ['info']), (2, ['warning']), (8, ['error'])])
def test_automatic_replication_records_only_actionable_activity(roots_db, monkeypatch, code, levels):
    main = roots_db
    job = main.create_job(main.JobIn(
        name='Continuous migration',
        source=r'\\FS01\Shares\Finance',
        destination=r'\\FS02\Shares\Finance',
        schedule_type='continuous',
    ))
    jid = job['id']
    main.sql('UPDATE jobs SET continuous_ready=1,dry_run_ok=1 WHERE id=?', (jid,))
    recorded = []
    monkeypatch.setattr(main, 'event', lambda jid, level, message: recorded.append(level))

    class Process:
        stdout = []

        def wait(self):
            return code

    monkeypatch.setattr(main.engine, 'command', lambda *args, **kwargs: ['robocopy.exe'])
    monkeypatch.setattr(main.subprocess, 'Popen', lambda *args, **kwargs: Process())
    queued = main.submit(jid, 'sync', scheduled=True, automatic_replication=True)
    run = main.claim_next_run()
    assert run['id'] == queued['run_id']
    main.run_job(jid, 'sync', run['id'])

    assert recorded == levels
    assert main.get_job(jid)['last_exit'] == code
    assert main.sql('SELECT exit_code FROM runs WHERE id=?', (run['id'],), one=True)['exit_code'] == code


def test_pause_holds_queued_replication_until_resume(roots_db):
    main = roots_db
    job = main.create_job(main.JobIn(
        name='Continuous migration',
        source=r'\\FS01\Shares\Finance',
        destination=r'\\FS02\Shares\Finance',
        schedule_type='continuous',
    ))
    jid = job['id']
    main.sql('UPDATE jobs SET continuous_ready=1,dry_run_ok=1 WHERE id=?', (jid,))
    queued = main.submit(jid, 'sync', scheduled=True, automatic_replication=True)

    assert main.set_replication_pause(jid, 'pause')['replication_paused'] is True
    assert main.continuous_job_status(True)[0]['state'] == 'paused'
    assert main.claim_next_run() is None
    assert main.get_job(jid)['status'] == 'queued'

    assert main.set_replication_pause(jid, 'resume')['replication_paused'] is False
    try:
        assert main.claim_next_run()['id'] == queued['run_id']
        assert main.set_replication_pause(jid, 'pause')['replication_paused'] is True
        assert main.get_job(jid)['status'] == 'running'
    finally:
        with main.LOCK:
            main.ACTIVE.discard(jid)


def test_pause_active_run_and_stop_resumed_run(roots_db, monkeypatch):
    main = roots_db
    job = main.create_job(main.JobIn(
        name='Migration', source=r'\\FS01\Shares\Finance', destination=r'\\FS02\Shares\Finance',
    ))
    jid = job['id']
    run_id = main.submit(jid, 'sync')['run_id']
    assert main.claim_next_run()['id'] == run_id
    assert main.control_run(jid, run_id, 'pause')['status'] == 'pausing'
    terminated = threading.Event()

    class Process:
        returncode = None

        @property
        def stdout(self):
            assert terminated.wait(5)
            return []

        def terminate(self):
            terminated.set()

        def poll(self):
            return self.returncode

        def wait(self):
            return 1

    monkeypatch.setattr(main.engine, 'command', lambda *args, **kwargs: ['robocopy.exe'])
    monkeypatch.setattr(main.subprocess, 'Popen', lambda *args, **kwargs: Process())
    main.run_job(jid, 'sync', run_id)
    assert terminated.is_set()
    assert main.get_job(jid)['status'] == 'paused'
    assert main.control_run(jid, run_id, 'resume')['status'] == 'queued'
    resumed = main.sql('SELECT MAX(id) AS id FROM runs WHERE job_id=?', (jid,), one=True)['id']
    with pytest.raises(HTTPException) as stale:
        main.control_run(jid, run_id, 'stop')
    assert stale.value.status_code == 409
    assert main.control_run(jid, resumed, 'stop')['status'] == 'cancelled'
    assert main.wait_for_run(jid, resumed)['status'] == 'cancelled'
    assert main.claim_next_run() is None


@pytest.mark.parametrize(('interrupt_confirmed', 'expected'), [(True, 'stopped'), (False, 'failed')])
def test_pending_stop_uses_confirmed_process_outcome(roots_db, interrupt_confirmed, expected):
    main = roots_db
    job = main.create_job(main.JobIn(
        name='Migration', source=r'\\FS01\Shares\Finance', destination=r'\\FS02\Shares\Finance',
    ))
    jid = job['id']
    run_id = main.submit(jid, 'sync')['run_id']
    assert main.claim_next_run()['id'] == run_id
    try:
        assert main.control_run(jid, run_id, 'stop')['status'] == 'stopping'
        assert main.jobs()[0]['interrupt_action'] == 'stop'
        with pytest.raises(HTTPException) as busy:
            main.delete_job(jid)
        assert busy.value.status_code == 409
        finished = main.finish_run(jid, run_id, 'failed', 8, 'Copy error',
                                   interrupted=interrupt_confirmed, error='Copy error')
        assert finished == expected
        assert main.get_job(jid)['status'] == main.runs(jid)[0]['status'] == expected
        assert main.get_job(jid)['last_error'] == (None if interrupt_confirmed else 'Copy error')
        assert main.runs(jid)[0]['interrupt_action'] is None
    finally:
        main.ACTIVE.discard(jid)


def test_delete_job_removes_schedule_and_history_without_reusing_id(roots_db):
    main = roots_db
    data = main.JobIn(name='Migration', source=r'\\FS01\Shares\Finance',
                      destination=r'\\FS02\Shares\Finance', schedule_type='cron', cron='0 1 * * *')
    jid = main.create_job(data)['id']
    try:
        run_id = main.submit(jid, 'sync')['run_id']
        main.control_run(jid, run_id, 'stop')
        assert main.SCHED.get_job(str(jid)) is not None
        assert main.delete_job(jid) == {'deleted': True}
        assert main.SCHED.get_job(str(jid)) is None
        assert not main.sql('SELECT id FROM runs WHERE job_id=?', (jid,))
        assert not main.sql('SELECT id FROM events WHERE job_id=?', (jid,))
        assert main.submit(jid, 'sync', scheduled=True) is False
        replacement = main.create_job(data)['id']
        assert replacement > jid
        main.delete_job(replacement)
    finally:
        if main.SCHED.get_job(str(jid)):
            main.SCHED.remove_job(str(jid))


def test_log_retention_preserves_recent_active_and_unrelated_files(roots_db, tmp_path, monkeypatch):
    main = roots_db
    monkeypatch.setattr(main, 'STATE', tmp_path)
    logs = tmp_path / 'logs'
    logs.mkdir()
    expired = logs / 'job-1-sync-20260101T000000000000Z.log'
    active = logs / 'job-2-dry-run-20260101T000000000000Z.log'
    recent = logs / 'job-3-final-20260101T000000000000Z.log'
    unrelated = logs / 'unrelated.log'
    worker_archive = tmp_path / 'replication-worker.log.2026-01-01'
    old = time.time() - 8 * 86400
    for path in (expired, active, recent, unrelated, worker_archive):
        path.touch()
        if path != recent:
            os.utime(path, (old, old))
    main.sql("INSERT INTO runs(status,log_file) VALUES('running',?)", (str(active),))
    main.purge_expired_logs()
    assert not expired.exists()
    assert not worker_archive.exists()
    assert all(path.exists() for path in (active, recent, unrelated))


def test_editing_job_resets_readiness_and_cutover_attestations(roots_db):
    main = roots_db
    job = main.create_job(main.JobIn(
        name='Editable migration',
        source=r'\\FS01\Shares\Finance',
        destination=r'\\FS02\Shares\Finance',
        schedule_type='continuous',
    ))
    main.sql(
        '''UPDATE jobs SET dry_run_ok=1,continuous_ready=1,validated=1,frozen=1,
           approved=1,final_verified=1 WHERE id=?''',
        (job['id'],),
    )

    updated = main.update_job(job['id'], main.JobIn(
        name='Updated migration',
        source=r'\\FS01\Shares\Finance',
        destination=r'\\FS02\Shares\Finance',
        schedule_type='manual',
    ))

    assert updated['name'] == 'Updated migration'
    assert updated['schedule_type'] == 'manual'
    assert updated['status'] == 'idle'
    assert updated['dry_run_ok'] == 0
    assert updated['continuous_ready'] == 0
    assert updated['validated'] == updated['frozen'] == updated['approved'] == 0
    assert updated['final_verified'] == 0
    assert updated['last_exit'] is None
    assert updated['last_started'] is None
    assert updated['last_finished'] is None


def test_ad_settings_persist_and_admin_group_inherits_operator_access(roots_db):
    main = roots_db
    settings = main.update_ad_settings(main.ADSettingsIn(
        ldap_url='ldap://dc.example.com:389',
        search_base='DC=example,DC=com',
        operator_group_dn='CN=DataMover Operators,OU=Groups,DC=example,DC=com',
        admin_group_dn='CN=DataMover Administrators,OU=Groups,DC=example,DC=com',
    ))

    assert settings['enabled'] is True
    assert main.get_ad_settings() == settings
    assert main.ad_group_roles(
        ['CN=DataMover Administrators,OU=Groups,DC=example,DC=com'], settings
    ) == (True, True)
    assert main.ad_group_roles(['CN=Other,OU=Groups,DC=example,DC=com'], settings) == (False, False)
    with pytest.raises(ValidationError):
        main.ADSettingsIn(
            ldap_url='ldap://dc.example.com:389',
            search_base='DC=example,DC=com',
            operator_group_dn='CN=DataMover Operators,OU=Groups,DC=example,DC=com',
            admin_group_dn='cn=datamover operators,ou=groups,dc=example,dc=com',
        )


def test_async_run_is_persistently_queued_for_worker(roots_db):
    main = roots_db
    job = main.create_job(main.JobIn(
        name='Queued migration',
        source=r'\\FS01\Shares\Finance',
        destination=r'\\FS02\Shares\Finance',
    ))

    result = main.submit(job['id'], 'sync')

    assert result['accepted'] is True
    assert result['queued'] is True
    assert main.get_job(job['id'])['status'] == 'queued'
    assert main.sql('SELECT status FROM runs WHERE id=?', (result['run_id'],), one=True)['status'] == 'queued'


def test_synchronous_execution_waits_for_worker_result(roots_db, monkeypatch):
    main = roots_db
    main.sql(
        'INSERT INTO worker_heartbeats(name,updated) VALUES(?,?)',
        ('replication', main.now()),
    )
    job = main.create_job(main.JobIn(
        name='Synchronous migration',
        source=r'\\FS01\Shares\Finance',
        destination=r'\\FS02\Shares\Finance',
        execution_mode='sync',
    ))

    def finish_inline(jid, mode, run_id):
        main.sql(
            'UPDATE runs SET status=?,finished=?,exit_code=? WHERE id=?',
            ('success', main.now(), 0, run_id),
        )
        main.sql(
            'UPDATE jobs SET status=?,phase=?,last_exit=?,last_finished=?,last_error=NULL WHERE id=?',
            ('success', mode, 0, main.now(), jid),
        )
        with main.LOCK:
            main.ACTIVE.discard(jid)

    monkeypatch.setattr(main, 'run_job', finish_inline)
    worker_stopped = threading.Event()

    def consume_run():
        while not worker_stopped.is_set():
            run = main.claim_next_run()
            if run:
                main.run_job(run['job_id'], run['mode'], run['id'])
                return
            worker_stopped.wait(0.01)

    worker_thread = threading.Thread(target=consume_run)
    worker_thread.start()
    result = main.submit(job['id'], 'sync')
    worker_thread.join(timeout=5)

    assert not worker_thread.is_alive()
    assert result['accepted'] is True
    assert result['queued'] is False
    assert result['status'] == 'success'


def test_approval_is_rejected_while_job_is_running(roots_db):
    main = roots_db
    job = main.create_job(main.JobIn(
        name='Cutover migration',
        source=r'\\FS01\Shares\Finance',
        destination=r'\\FS02\Shares\Finance',
    ))
    main.sql(
        'UPDATE jobs SET dry_run_ok=1,validated=1,frozen=1 WHERE id=?',
        (job['id'],),
    )
    main.ACTIVE.add(job['id'])
    try:
        with pytest.raises(HTTPException) as error:
            main.approve(
                job['id'],
                main.Confirmation(note='Approved after validation', confirmed=True),
            )
        assert error.value.status_code == 409
    finally:
        main.ACTIVE.discard(job['id'])
