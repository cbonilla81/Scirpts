import pytest
from fastapi import HTTPException

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
