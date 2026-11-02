from fastapi import APIRouter,Depends,HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session
from datetime import datetime
from uuid import uuid4
from app.models.db import SessionLocal,Server,Job,Baseline,FirmwareSnapshot,MaintenanceWindow
from app.core.security import decrypt
from app.core.config import settings
from app.services.redfish import RedfishClient
from app.services.compliance import compare
router=APIRouter(tags=['fleet'])
def db():
 d=SessionLocal()
 try: yield d
 finally:d.close()
class BaselineIn(BaseModel): model:str; component:str; target_version:str; image_uri:str=''; approved:bool=True
class GroupIn(BaseModel): server_ids:list[int]; group_name:str
class RollingIn(BaseModel): server_ids:list[int]; component:str; image_uri:str|None=None; stop_on_failure:bool=True
class WindowIn(BaseModel): name:str; group_name:str='Default'; start_hour:int=0; end_hour:int=23; enabled:bool=True
@router.get('/baselines')
def baselines(d:Session=Depends(db)): return d.query(Baseline).all()
@router.post('/baselines')
def baseline(x:BaselineIn,d:Session=Depends(db)):
 b=d.query(Baseline).filter_by(model=x.model,component=x.component).first() or Baseline(model=x.model,component=x.component); b.target_version=x.target_version;b.image_uri=x.image_uri;b.approved=x.approved;b.updated_at=datetime.utcnow();d.add(b);d.commit();d.refresh(b);return b
@router.delete('/baselines/{bid}')
def delbaseline(bid:int,d:Session=Depends(db)):
 b=d.get(Baseline,bid)
 if not b: raise HTTPException(404,'Baseline not found')
 d.delete(b);d.commit();return {'ok':True}
@router.post('/groups')
def group(x:GroupIn,d:Session=Depends(db)):
 for s in d.query(Server).filter(Server.id.in_(x.server_ids)): s.group_name=x.group_name
 d.commit();return {'updated':len(x.server_ids)}
@router.get('/groups')
def groups(d:Session=Depends(db)): return sorted({x[0] for x in d.query(Server.group_name).all()})
@router.post('/servers/{sid}/compliance')
def compliance(sid:int,d:Session=Depends(db)):
 s=d.get(Server,sid)
 if not s: raise HTTPException(404,'Server not found')
 c=RedfishClient(s.address,s.username,decrypt(s.password_enc)); fw=c.firmware_inventory(); d.query(FirmwareSnapshot).filter_by(server_id=sid).delete(); out=[]
 for item in fw:
  d.add(FirmwareSnapshot(server_id=sid,component=item['name'],version=item['version'],health=item.get('health','Unknown')))
  b=d.query(Baseline).filter_by(model=s.model,component=item['name'],approved=True).first(); out.append({**item,'target':b.target_version if b else None,'image_uri':b.image_uri if b else None,'status':compare(item['version'],b.target_version) if b else 'No Baseline'})
 d.commit();return out
@router.get('/servers/{sid}/preflight')
def preflight(sid:int,d:Session=Depends(db)):
 s=d.get(Server,sid)
 if not s: raise HTTPException(404,'Server not found')
 return RedfishClient(s.address,s.username,decrypt(s.password_enc)).preflight()
@router.get('/windows')
def windows(d:Session=Depends(db)): return d.query(MaintenanceWindow).all()
@router.post('/windows')
def window(x:WindowIn,d:Session=Depends(db)):
 w=MaintenanceWindow(**x.model_dump());d.add(w);d.commit();d.refresh(w);return w
@router.post('/rolling-update')
def rolling(x:RollingIn,d:Session=Depends(db)):
 batch=str(uuid4())[:8]; results=[]
 for sid in x.server_ids:
  s=d.get(Server,sid)
  if not s: continue
  c=RedfishClient(s.address,s.username,decrypt(s.password_enc)); pf=c.preflight()
  if not pf['passed']:
   j=Job(server_id=sid,action='Rolling '+x.component,status='Preflight Failed',detail='; '.join(pf['issues']),batch_id=batch);d.add(j);d.commit();results.append({'server_id':sid,'status':j.status})
   if x.stop_on_failure: break
   continue
  uri=x.image_uri
  if not uri:
   b=d.query(Baseline).filter_by(model=s.model,component=x.component,approved=True).first();uri=b.image_uri if b else None
  if not uri: raise HTTPException(400,f'No approved image URI for {s.model} / {x.component}')
  j=Job(server_id=sid,action='Rolling '+x.component,status='Running',detail=uri,batch_id=batch);d.add(j);d.commit();d.refresh(j)
  try:
   r=c.install_uri(uri);j.task_uri=r.get('task_uri',''); state=c.task(j.task_uri) if j.task_uri else {};j.status='Completed' if settings.simulation_mode else state.get('TaskState','Submitted');j.detail=str(state or r)
  except Exception as e: j.status='Failed';j.detail=str(e)
  j.updated_at=datetime.utcnow();d.commit();results.append({'server_id':sid,'job_id':j.id,'status':j.status})
  if j.status in ('Failed','Exception','Killed') and x.stop_on_failure: break
 return {'batch_id':batch,'results':results}
