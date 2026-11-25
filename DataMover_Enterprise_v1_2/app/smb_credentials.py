"""Worker-owned SMB connections with leases shared by copies and watchers."""
import base64
import json
import logging
import os
import tempfile
import threading
from contextlib import contextmanager
from pathlib import Path, PureWindowsPath

from .engine import EngineError, normalize_path


LOGGER = logging.getLogger('datamover.replication')
CRYPTPROTECT_UI_FORBIDDEN = 0x1
CRYPTPROTECT_LOCAL_MACHINE = 0x4


def share_root(path):
    return PureWindowsPath(path).drive.rstrip('\\')


def server_name(path):
    drive = share_root(path)
    return drive[2:].split('\\', 1)[0].casefold() if drive.startswith('\\\\') else None


def direct_share(path):
    share = normalize_path(path).rstrip('\\')
    if not server_name(share) or share_root(share) != share:
        raise EngineError('Enter a direct UNC share such as \\\\server.example\\Data')
    return share


def load_credentials(path):
    path = Path(path)
    if not path.is_absolute() or str(path).startswith('\\\\'):
        raise EngineError('Use an absolute local path for DATAMOVER_SMB_CREDENTIALS')
    try:
        entries = json.loads(path.read_text(encoding='utf-8-sig'))
        if not isinstance(entries, list):
            raise ValueError
        credentials = {}
        for entry in entries:
            share = direct_share(entry['share'])
            server = server_name(share)
            username = entry['username']
            if server in credentials or not isinstance(username, str) or not username.strip() or '\x00' in username:
                raise ValueError
            encrypted = base64.b64decode(entry['password_dpapi'], validate=True)
            if not encrypted:
                raise ValueError
            credentials[server] = (share, username, encrypted)
        return credentials
    except (OSError, ValueError, TypeError, KeyError):
        raise EngineError('Unable to read the worker SMB credential file') from None


def save_credentials(path, credentials):
    entries = [
        {'share': share, 'username': username, 'password_dpapi': base64.b64encode(encrypted).decode('ascii')}
        for share, username, encrypted in credentials.values()
    ]
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=Path(path).parent,
                                         prefix='.smb-', suffix='.tmp', delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(entries, stream)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def protect_password(password):
    import pywintypes
    import win32crypt

    try:
        return win32crypt.CryptProtectData(password.encode('utf-8'), 'DataMover SMB', None, None, None,
                                           CRYPTPROTECT_UI_FORBIDDEN | CRYPTPROTECT_LOCAL_MACHINE)
    except (pywintypes.error, UnicodeError):
        raise EngineError('Unable to encrypt the SMB credential') from None


class ShareConnections:
    def __init__(self, config_path=None):
        self.config_path = config_path
        self.credentials = {}
        self.leases = {}
        self.lock = threading.Lock()
        self.reload()

    def reload(self):
        if self.config_path:
            credentials = load_credentials(self.config_path)
            with self.lock:
                changed = {server for server in self.credentials.keys() | credentials.keys()
                           if self.credentials.get(server) != credentials.get(server)}
                self.credentials = credentials
            return changed
        return set()

    @staticmethod
    def open_share(credential):
        import pywintypes
        import win32crypt
        import win32netcon
        import win32wnet

        share, username, encrypted = credential
        try:
            password = win32crypt.CryptUnprotectData(
                encrypted, None, None, None, CRYPTPROTECT_UI_FORBIDDEN,
            )[1].decode('utf-8')
        except (pywintypes.error, UnicodeError):
            raise EngineError(f'Unable to decrypt the SMB credential for {share}') from None
        resource = win32wnet.NETRESOURCE()
        resource.dwType = win32netcon.RESOURCETYPE_DISK
        resource.lpRemoteName = share
        try:
            win32wnet.WNetAddConnection2(resource, password, username, win32netcon.CONNECT_TEMPORARY)
        except pywintypes.error as exc:
            raise EngineError(f'SMB connection failed for {share} (Windows error {exc.winerror})') from None
        finally:
            del password

    @staticmethod
    def close_share(share):
        import pywintypes
        import win32wnet

        try:
            win32wnet.WNetCancelConnection2(share, 0, False)
        except pywintypes.error as exc:
            if exc.winerror != 2250:  # ERROR_NOT_CONNECTED
                raise EngineError(f'SMB disconnect failed for {share} (Windows error {exc.winerror})') from None

    @contextmanager
    def connect(self, path):
        server = server_name(path)
        if not self.config_path or not server:
            yield
            return
        with self.lock:
            credential = self.credentials.get(server)
            if credential and share_root(path).casefold() != credential[0].casefold():
                raise EngineError(f'Use the configured share {credential[0]} for this SMB server')
            previous, count = self.leases.get(server, (None, 0))
            if count and previous != credential:
                raise EngineError(f'SMB credentials changed for {server}. Retry after active copies finish.')
            if not count:
                if previous:
                    self.close_share(previous[0])
                    del self.leases[server]
                if credential:
                    self.open_share(credential)
            self.leases[server] = (credential, count + 1)
        try:
            yield
        finally:
            with self.lock:
                credential, count = self.leases[server]
                self.leases[server] = (credential, count - 1)
                if count == 1:
                    try:
                        if credential:
                            self.close_share(credential[0])
                        del self.leases[server]
                    except EngineError as exc:
                        LOGGER.warning('%s', exc)
