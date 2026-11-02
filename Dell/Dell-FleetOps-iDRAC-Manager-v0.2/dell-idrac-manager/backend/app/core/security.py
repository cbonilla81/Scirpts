import base64, hashlib
from cryptography.fernet import Fernet
from app.core.config import settings
key=base64.urlsafe_b64encode(hashlib.sha256(settings.secret_key.encode()).digest())
f=Fernet(key)
def encrypt(v:str)->str: return f.encrypt(v.encode()).decode()
def decrypt(v:str)->str: return f.decrypt(v.encode()).decode()
