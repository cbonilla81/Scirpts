import requests,time
from app.core.config import settings
class RedfishClient:
 def __init__(self,address,username,password): self.base=f"https://{address}"; self.auth=(username,password)
 def _req(self,method,path,**kw):
  r=requests.request(method,self.base+path,auth=self.auth,verify=settings.verify_tls,timeout=60,**kw); r.raise_for_status(); return r
 def get(self,path): return self._req('GET',path).json()
 def inventory(self):
  if settings.simulation_mode: return {"model":"PowerEdge R750","service_tag":"SIM1234","bios_version":"1.9.2","idrac_version":"7.10.30.00","health":"OK","power_state":"On"}
  sys=self.get('/redfish/v1/Systems/System.Embedded.1'); mgr=self.get('/redfish/v1/Managers/iDRAC.Embedded.1')
  return {"model":sys.get('Model','Unknown'),"service_tag":sys.get('SKU') or sys.get('SerialNumber','Unknown'),"bios_version":sys.get('BiosVersion','Unknown'),"idrac_version":mgr.get('FirmwareVersion','Unknown'),"health":sys.get('Status',{}).get('Health','Unknown'),"power_state":sys.get('PowerState','Unknown')}
 def firmware_inventory(self):
  if settings.simulation_mode: return [{"name":"iDRAC","version":"7.10.30.00","health":"OK"},{"name":"BIOS","version":"1.9.2","health":"OK"},{"name":"PERC","version":"52.21.0-4606","health":"OK"}]
  data=self.get('/redfish/v1/UpdateService/FirmwareInventory'); out=[]
  for m in data.get('Members',[]):
   i=self.get(m['@odata.id']); out.append({"name":i.get('Name','Unknown'),"version":i.get('Version','Unknown'),"health":i.get('Status',{}).get('Health','Unknown')})
  return out
 def preflight(self):
  inv=self.inventory(); issues=[]
  if inv['health'] not in ('OK','Warning'): issues.append('System health is '+inv['health'])
  if inv['power_state'] != 'On': issues.append('Server is not powered on')
  return {"passed":not issues,"issues":issues,"inventory":inv}
 def install_uri(self,image_uri):
  if settings.simulation_mode: time.sleep(.2); return {"simulated":True,"task_uri":"/redfish/v1/TaskService/Tasks/SIM-1","image":image_uri}
  r=self._req('POST','/redfish/v1/UpdateService/Actions/UpdateService.SimpleUpdate',json={"ImageURI":image_uri,"TransferProtocol":"HTTPS"})
  body=r.json() if r.content else {}; return {"task_uri":r.headers.get('Location') or body.get('@odata.id',''),"response":body}
 def task(self,uri):
  if settings.simulation_mode: return {"TaskState":"Completed","PercentComplete":100}
  return self.get(uri)
