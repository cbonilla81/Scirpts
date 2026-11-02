from sqlalchemy import create_engine, Column, Integer, String, Boolean, DateTime, Text, ForeignKey
from sqlalchemy.orm import declarative_base, sessionmaker
from datetime import datetime
from app.core.config import settings
engine=create_engine(settings.database_url, connect_args={"check_same_thread":False} if settings.database_url.startswith("sqlite") else {})
SessionLocal=sessionmaker(bind=engine, autoflush=False, autocommit=False); Base=declarative_base()
class Server(Base):
 __tablename__="servers"; id=Column(Integer,primary_key=True); name=Column(String,nullable=False); address=Column(String,unique=True,nullable=False); username=Column(String,nullable=False); password_enc=Column(Text,nullable=False); model=Column(String,default="Unknown"); service_tag=Column(String,default="Unknown"); bios_version=Column(String,default="Unknown"); idrac_version=Column(String,default="Unknown"); health=Column(String,default="Unknown"); power_state=Column(String,default="Unknown"); enabled=Column(Boolean,default=True); last_scan=Column(DateTime); group_name=Column(String,default="Default")
class Job(Base):
 __tablename__="jobs"; id=Column(Integer,primary_key=True); server_id=Column(Integer,nullable=True); action=Column(String,nullable=False); status=Column(String,default="Queued"); detail=Column(Text,default=""); task_uri=Column(Text,default=""); batch_id=Column(String,default=""); created_at=Column(DateTime,default=datetime.utcnow); updated_at=Column(DateTime,default=datetime.utcnow)
class Baseline(Base):
 __tablename__="baselines"; id=Column(Integer,primary_key=True); model=Column(String,nullable=False); component=Column(String,nullable=False); target_version=Column(String,nullable=False); image_uri=Column(Text,default=""); approved=Column(Boolean,default=True); updated_at=Column(DateTime,default=datetime.utcnow)
class FirmwareSnapshot(Base):
 __tablename__="firmware_snapshots"; id=Column(Integer,primary_key=True); server_id=Column(Integer,ForeignKey('servers.id')); component=Column(String); version=Column(String); health=Column(String,default="Unknown"); scanned_at=Column(DateTime,default=datetime.utcnow)
class MaintenanceWindow(Base):
 __tablename__="maintenance_windows"; id=Column(Integer,primary_key=True); name=Column(String,nullable=False); group_name=Column(String,default="Default"); start_hour=Column(Integer,default=0); end_hour=Column(Integer,default=23); enabled=Column(Boolean,default=True)
