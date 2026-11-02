from pydantic_settings import BaseSettings
class Settings(BaseSettings):
 database_url:str="sqlite:///./data/idrac.db"; secret_key:str="CHANGE-ME-32-BYTE-SECRET"; simulation_mode:bool=True; verify_tls:bool=False; admin_user:str="admin"; admin_password:str="ChangeMe!123"; require_maintenance_window:bool=False
 class Config: env_file=".env"
settings=Settings()
