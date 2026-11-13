"""Windows Robocopy-only command building and process helpers."""
import os
import re
import shutil
from pathlib import PureWindowsPath

class EngineError(ValueError):
    pass

def normalize_path(value):
    if not isinstance(value, str) or not value.strip():
        raise EngineError('Path required')
    value = value.strip().rstrip('\\/')
    if not value or any(ch in value for ch in '\r\n\x00"*?<>|'):
        raise EngineError('Unsafe path characters')
    if not (re.match(r'^\\\\[^\\]+\\[^\\]+(?:\\.*)?$', value) or re.match(r'^[A-Za-z]:\\', value)):
        raise EngineError('Use an absolute Windows drive path or UNC share')
    parts = PureWindowsPath(value).parts
    if '..' in parts or '.' in parts:
        raise EngineError('Relative path segments prohibited')
    return str(PureWindowsPath(value))

def within(path, root):
    p, r = normalize_path(path).casefold().rstrip('\\'), normalize_path(root).casefold().rstrip('\\')
    return p == r or p.startswith(r + '\\')

def validate_pair(source, destination, roots):
    src, dst = normalize_path(source), normalize_path(destination)
    if src.casefold() == dst.casefold():
        raise EngineError('Source and destination must differ')
    if within(dst, src) or within(src, dst):
        raise EngineError('Nested source/destination paths are prohibited')
    if not any(within(src, root) for root in roots) or not any(within(dst, root) for root in roots):
        raise EngineError('Path is outside approved roots')
    return src, dst

def executable():
    if os.name != 'nt':
        raise EngineError('Robocopy workers require Windows')
    exe = shutil.which('robocopy.exe')
    if not exe:
        raise EngineError('robocopy.exe was not found on PATH')
    return exe

def command(source, destination, *, dry_run=False, final=False, source_wins=False, log_path=None, threads=16):
    if not 1 <= int(threads) <= 32:
        raise EngineError('Threads must be between 1 and 32')
    # /E does not delete destination-only files. /XJ prevents junction traversal.
    # /COPYALL requires backup/security privileges and compatible NTFS destination.
    args = [executable(), source, destination, '/E', '/COPYALL', '/DCOPY:DAT', '/ZB',
            f'/MT:{int(threads)}', '/R:3', '/W:5', '/XJ', '/NP', '/TEE', '/BYTES']
    if source_wins:
        args += ['/IS', '/IT', '/IM']
    if final:
        args += ['/SECFIX', '/TIMFIX']
    if dry_run:
        args += ['/L', '/R:0', '/W:0']
    if log_path:
        args.append('/LOG:' + str(log_path))
    return args

def exit_success(code):
    return 0 <= code < 8
