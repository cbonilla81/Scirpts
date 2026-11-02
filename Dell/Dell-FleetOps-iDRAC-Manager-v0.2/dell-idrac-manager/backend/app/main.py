from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.models.db import Base,engine
from app.api.servers import router as servers
from app.api.jobs import router as jobs
from app.api.fleet import router as fleet
Base.metadata.create_all(engine)
app=FastAPI(title='Dell FleetOps iDRAC Manager',version='0.2.0')
app.add_middleware(CORSMiddleware,allow_origins=['*'],allow_methods=['*'],allow_headers=['*'])
app.include_router(servers,prefix='/api');app.include_router(jobs,prefix='/api');app.include_router(fleet,prefix='/api')
@app.get('/api/health')
def health(): return {'status':'ok','version':'0.2.0'}
