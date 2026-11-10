import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

os.environ['DATAMOVER_API_KEY']='a'*48
os.environ['DATAMOVER_ALLOWED_ROOTS']='remote:bucket;/srv/source;/srv/dest'
os.environ['DATAMOVER_STATE']=tempfile.mkdtemp()
from fastapi.testclient import TestClient
from app.main import app, command_for, check_path

class Tests(unittest.TestCase):
    def setUp(self):
        self.client=TestClient(app)
        self.h={'X-API-Key':'a'*48}
    def test_auth(self):
        self.assertEqual(self.client.get('/api/jobs').status_code,401)
        self.assertEqual(self.client.get('/api/jobs',headers=self.h).status_code,200)
    def test_allowlist(self):
        with self.assertRaises(ValueError): check_path('/etc/passwd')
        with self.assertRaises(ValueError): check_path('/srv/source-evil')
        self.assertEqual(check_path('remote:bucket/file'),'remote:bucket/file')
    def test_create_and_guard_cutover(self):
        r=self.client.post('/api/jobs',headers=self.h,json={'name':'test','source':'/srv/source','destination':'/srv/dest','engine':'rclone','cron':'0 2 * * *'})
        self.assertEqual(r.status_code,200,r.text)
        jid=r.json()['id']
        self.assertEqual(self.client.post(f'/api/jobs/{jid}/approve',headers=self.h,json={'note':'change ticket 123','source_frozen':True,'confirm':'APPROVE FINAL SYNC'}).status_code,409)
        self.assertEqual(self.client.post(f'/api/jobs/{jid}/final-sync',headers=self.h).status_code,409)
    def test_no_delete(self):
        cmd=command_for({'engine':'rclone','source':'/srv/source','destination':'/srv/dest'})
        self.assertEqual(cmd[1],'copy')
        self.assertNotIn('sync',cmd)

if __name__=='__main__': unittest.main()

class DryRunTests(unittest.TestCase):
    def test_rclone_dry_run_command(self):
        cmd=command_for({'engine':'rclone','source':'/srv/source','destination':'/srv/dest'},dry_run=True)
        self.assertIn('--dry-run',cmd)
        self.assertEqual(cmd[1],'copy')
    def test_dry_run_endpoint_guard(self):
        client=TestClient(app)
        h={'X-API-Key':'a'*48}
        r=client.post('/api/jobs',headers=h,json={'name':'dry-run test','source':'/srv/source','destination':'/srv/dest','engine':'rclone'})
        self.assertEqual(r.status_code,200,r.text)
        jid=r.json()['id']
        self.assertEqual(client.post(f'/api/jobs/{jid}/handoff',headers=h,json={'confirm':'HANDOFF VERIFIED','note':'verified manually'}).status_code,409)
        self.assertEqual(client.get(f'/api/jobs/{jid}/rollback-plan',headers=h).status_code,200)
