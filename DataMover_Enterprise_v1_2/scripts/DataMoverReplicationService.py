import os
import sys
import threading
import traceback
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
SITE_PACKAGES = ROOT / '.venv' / 'Lib' / 'site-packages'
# pythonservice.exe may not process the venv's pywin32 .pth bootstrap.
for import_path in (
    SITE_PACKAGES,
    SITE_PACKAGES / 'win32',
    SITE_PACKAGES / 'win32' / 'lib',
):
    if import_path.is_dir() and str(import_path) not in sys.path:
        sys.path.insert(0, str(import_path))

_DLL_DIRECTORY_HANDLES = []
PYWIN32_DLLS = SITE_PACKAGES / 'pywin32_system32'
if PYWIN32_DLLS.is_dir():
    _DLL_DIRECTORY_HANDLES.append(os.add_dll_directory(str(PYWIN32_DLLS)))

import servicemanager
import win32service
import win32serviceutil


class DataMoverReplicationService(win32serviceutil.ServiceFramework):
    _svc_name_ = 'DataMoverReplication'
    _svc_display_name_ = 'DataMover Continuous Replication Worker'
    _svc_description_ = 'Watches approved DataMover source roots and runs queued Robocopy jobs.'

    def __init__(self, args):
        super().__init__(args)
        self.stop_event = threading.Event()

    def SvcStop(self):
        self.ReportServiceStatus(win32service.SERVICE_STOP_PENDING)
        self.stop_event.set()

    def SvcDoRun(self):
        try:
            from app.replication_worker import run_worker
            run_worker(self.stop_event)
        except Exception:
            servicemanager.LogErrorMsg(traceback.format_exc()[-3000:])
            raise


if __name__ == '__main__':
    win32serviceutil.HandleCommandLine(DataMoverReplicationService)
