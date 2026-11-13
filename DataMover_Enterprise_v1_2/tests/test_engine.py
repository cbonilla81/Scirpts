import pytest
from unittest.mock import patch
from app.engine import normalize_path, validate_pair, command, exit_success, EngineError

ROOTS = [r'\\FS01\Shares', r'\\FS02\Shares']

def test_unc_paths():
    assert normalize_path(r'\\FS01\Shares\Finance').lower().endswith('finance')
    assert validate_pair(r'\\FS01\Shares\Finance', r'\\FS02\Shares\Finance', ROOTS)
    assert validate_pair(
        r'\\files.example.com\Departments\Finance',
        r'\\FS02\Shares\Finance',
        [r'\\files.example.com\Departments', r'\\FS02\Shares'],
    )

def test_reject_path_traversal():
    with pytest.raises(EngineError):
        validate_pair(r'\\FS01\Shares\..\Admin', r'\\FS02\Shares\Finance', ROOTS)

def test_reject_outside_root():
    with pytest.raises(EngineError):
        validate_pair(r'\\FS01\Shares2\Finance', r'\\FS02\Shares\Finance', ROOTS)

def test_reject_nested():
    with pytest.raises(EngineError):
        validate_pair(r'C:\Data', r'C:\Data\Backup', ['C:\\'])

def test_dry_run_no_delete():
    with patch('app.engine.executable', return_value=r'C:\Windows\System32\robocopy.exe'):
        args = command(r'\\FS01\Shares\Finance', r'\\FS02\Shares\Finance', dry_run=True)
    assert '/L' in args and '/COPYALL' in args and '/XJ' in args
    assert '/MIR' not in args and '/PURGE' not in args

def test_final_security_repair():
    with patch('app.engine.executable', return_value='robocopy.exe'):
        args = command(r'C:\Source', r'D:\Dest', final=True)
    assert '/SECFIX' in args and '/TIMFIX' in args

def test_source_wins_includes_identical_and_modified_files():
    with patch('app.engine.executable', return_value='robocopy.exe'):
        args = command(r'C:\Source', r'D:\Dest', source_wins=True)
    assert all(option in args for option in ('/IS', '/IT', '/IM'))
    assert '/MIR' not in args and '/PURGE' not in args

def test_exit_code_bitmask():
    assert all(exit_success(i) for i in range(8))
    assert not exit_success(8)
