from fastapi import APIRouter
from app.models.db import SessionLocal,Job
router=APIRouter(prefix='/jobs',tags=['jobs'])
@router.get('')
def jobs():
 d=SessionLocal()
 try:return [{"id":j.id,"server_id":j.server_id,"action":j.action,"status":j.status,"detail":j.detail,"task_uri":j.task_uri,"batch_id":j.batch_id,"created_at":j.created_at} for j in d.query(Job).order_by(Job.id.desc()).limit(200)]
 finally:d.close()
