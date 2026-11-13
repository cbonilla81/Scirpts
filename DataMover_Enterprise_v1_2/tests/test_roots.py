import pytest
from datetime import datetime, timedelta
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


def test_synchronous_execution_waits_for_worker_result(roots_db, monkeypatch):
    main = roots_db
    job = main.create_job(main.JobIn(
        name='Synchronous migration',
        source=r'\\FS01\Shares\Finance',
        destination=r'\\FS02\Shares\Finance',
        execution_mode='sync',
    ))

    def finish_inline(jid, mode):
        main.sql('UPDATE jobs SET status=?,phase=? WHERE id=?', ('success', mode, jid))
        with main.LOCK:
            main.ACTIVE.discard(jid)

    monkeypatch.setattr(main, 'run_job', finish_inline)
    result = main.submit(job['id'], 'sync')

    assert result == {'accepted': True, 'queued': False, 'status': 'success', 'error': None}
