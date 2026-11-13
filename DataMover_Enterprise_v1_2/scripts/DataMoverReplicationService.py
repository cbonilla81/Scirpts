import sys
import threading
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import servicemanager
import win32service
import win32serviceutil

from app.replication_worker import run_worker


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
            run_worker(self.stop_event)
        except Exception as exc:
            servicemanager.LogErrorMsg(f'DataMover replication worker failed: {exc}')
            raise


if __name__ == '__main__':
    win32serviceutil.HandleCommandLine(DataMoverReplicationService)
