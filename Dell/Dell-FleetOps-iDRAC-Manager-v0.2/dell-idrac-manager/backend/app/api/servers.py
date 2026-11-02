from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session
from datetime import datetime
from app.models.db import SessionLocal, Server, Job
from app.core.security import encrypt,decrypt
from app.services.redfish import RedfishClient
router=APIRouter(prefix="/servers",tags=["servers"])
def db():
    s=SessionLocal()
    try: yield s
    finally: s.close()
class ServerIn(BaseModel): name:str; address:str; username:str; password:str
class UpdateIn(BaseModel): image_uri:str
@router.get("")
def list_servers(d:Session=Depends(db)):
    return [{"id":s.id,"name":s.name,"address":s.address,"model":s.model,"service_tag":s.service_tag,"bios_version":s.bios_version,"idrac_version":s.idrac_version,"health":s.health,"power_state":s.power_state,"last_scan":s.last_scan,"group_name":s.group_name} for s in d.query(Server).all()]
@router.post("")
def add_server(x:ServerIn,d:Session=Depends(db)):
    s=Server(name=x.name,address=x.address,username=x.username,password_enc=encrypt(x.password)); d.add(s); d.commit(); d.refresh(s); return {"id":s.id}
@router.delete('/{sid}')
def delete_server(sid:int,d:Session=Depends(db)):
    s=d.get(Server,sid)
    if not s: raise HTTPException(404,"Server not found")
    d.delete(s); d.commit(); return {"ok":True}
@router.post('/{sid}/scan')
def scan(sid:int,d:Session=Depends(db)):
    s=d.get(Server,sid)
    if not s: raise HTTPException(404,"Server not found")
    inv=RedfishClient(s.address,s.username,decrypt(s.password_enc)).inventory()
    for k,v in inv.items(): setattr(s,k,v)
    s.last_scan=datetime.utcnow(); d.commit(); return inv
@router.get('/{sid}/firmware')
def firmware(sid:int,d:Session=Depends(db)):
    s=d.get(Server,sid)
    if not s: raise HTTPException(404,"Server not found")
    return RedfishClient(s.address,s.username,decrypt(s.password_enc)).firmware_inventory()
@router.post('/{sid}/update')
def update(sid:int,x:UpdateIn,d:Session=Depends(db)):
    s=d.get(Server,sid)
    if not s: raise HTTPException(404,"Server not found")
    j=Job(server_id=sid,action="Firmware Update",status="Running",detail=x.image_uri); d.add(j); d.commit(); d.refresh(j)
    try:
        result=RedfishClient(s.address,s.username,decrypt(s.password_enc)).install_uri(x.image_uri); j.status="Submitted"; j.detail=str(result)
    except Exception as e: j.status="Failed"; j.detail=str(e)
    j.updated_at=datetime.utcnow(); d.commit(); return {"job_id":j.id,"status":j.status,"detail":j.detail}
