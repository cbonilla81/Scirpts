import re
def version_key(v): return tuple(int(x) for x in re.findall(r'\d+',str(v))[:6])
def compare(current,target):
 try:
  a,b=version_key(current),version_key(target)
  return 'Compliant' if a>=b else 'Update Available'
 except: return 'Unknown'
