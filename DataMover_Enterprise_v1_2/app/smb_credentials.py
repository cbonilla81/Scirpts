"""Worker-owned SMB connections with leases shared by copies and watchers."""
import base64
import json
import logging
import threading
from contextlib import contextmanager
from pathlib import Path, PureWindowsPath

from .engine import EngineError, normalize_path


LOGGER = logging.getLogger('datamover.replication')
CRYPTPROTECT_UI_FORBIDDEN = 0x1


class ShareConnections:
    def __init__(self, config_path=None):
        self.credentials = {}
        self.leases = {}
        self.lock = threading.Lock()
        if config_path:
            self.load(Path(config_path))

    def load(self, path):
        if not path.is_absolute():
            raise EngineError('Use an absolute path for DATAMOVER_SMB_CREDENTIALS')
        try:
            entries = json.loads(path.read_text(encoding='utf-8-sig'))
            if not isinstance(entries, list) or not entries:
                raise ValueError
            for entry in entries:
                share = normalize_path(entry['share']).rstrip('\\')
                server = self.server(share)
                username = entry['username']
                if (not server or PureWindowsPath(share).drive != share
                        or server in self.credentials or not isinstance(username, str)
                        or not username.strip() or '\x00' in username):
                    raise ValueError
                encrypted = base64.b64decode(entry['password_dpapi'], validate=True)
                if not encrypted:
                    raise ValueError
                self.credentials[server] = (share, username, encrypted)
        except (OSError, ValueError, TypeError, KeyError):
            raise EngineError('Invalid worker SMB credential file. Configure one direct UNC share per server.') from None

    @staticmethod
    def server(path):
        drive = PureWindowsPath(path).drive
        return drive[2:].split('\\', 1)[0].casefold() if drive.startswith('\\\\') else None

    @contextmanager
    def connect(self, path):
        server = self.server(path)
        credential = self.credentials.get(server)
        if credential is None:
            yield
            return
        share, username, encrypted = credential
        if PureWindowsPath(path).drive.casefold() != share.casefold():
            raise EngineError(f'Use the configured share {share} for this SMB server')

        import pywintypes
        import win32crypt
        import win32netcon
        import win32wnet

        with self.lock:
            if server not in self.leases:
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
            self.leases[server] = self.leases.get(server, 0) + 1
        try:
            yield
        finally:
            with self.lock:
                self.leases[server] -= 1
                if not self.leases[server]:
                    del self.leases[server]
                    try:
                        win32wnet.WNetCancelConnection2(share, 0, False)
                    except pywintypes.error as exc:
                        LOGGER.warning('SMB disconnect failed for %s (Windows error %s)', share, exc.winerror)
