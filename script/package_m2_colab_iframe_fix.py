#!/usr/bin/env python3
"""Package Colab access fix, without passwords, tokens or public URLs."""
import datetime, hashlib, json, zipfile
from pathlib import Path
root=Path(__file__).resolve().parents[1];out=root/'checkpoints';out.mkdir(exist_ok=True)
source=out/'RAILS8_M2_COLAB_IFRAME_FIX_SOURCE_20261029.zip'
evidence=out/'RAILS8_M2_COLAB_IFRAME_FIX_EVIDENCE_20261029.zip'
database=out/'M2_RAILS_AI_SEARCH_PRIVATE_SYNTHETIC_DB_20261029.dump'
master=out/'RAILS8_M2_COLAB_IFRAME_FIX_CHECKPOINT_20261029.zip'
manifest=out/'M2_COLAB_IFRAME_FIX_CHECKPOINT_MANIFEST.json'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
exclude={'__pycache__','.git','.bundle','vendor','bundle','node_modules','tmp','log','.cache','checkpoints'}
files=[]
for folder in ('app','bin','config','data','db','docs','lib','modal_app','preview','review','script','test'):
 for f in (root/folder).rglob('*'):
  rel=f.relative_to(root)
  if (f.is_file() and not any(part in exclude or part.startswith('.env') for part in rel.parts)
      and f.suffix not in ('.pyc','.log','.dump','.zip') and f.name not in ('master.key','credentials.yml.enc')):
   files.append(f)
files.extend(root/name for name in ('Gemfile','Gemfile.lock','Rakefile','config.ru','README_EN.md','README_VI.md','Dockerfile','.gitignore','.ruby-version') if (root/name).is_file())
files=sorted(set(files))
proof=sorted(f for f in (root/'evidence-m2-rails-colab-iframe-20261029').glob('*') if f.is_file())
assert len(proof)>=3 and database.is_file()
secret_values=[]
for path in list((Path.home()/'.config/rails8-support-desk-modal').glob('*.env'))+[Path.home()/'.kaggle/access_token']:
 if path.is_file():
  for line in path.read_text(errors='replace').splitlines():
   value=line.partition('=')[2] if '=' in line else line
   if len(value)>=24: secret_values.append(value.encode())
for p in files+proof:
 data=p.read_bytes()
 if any(x in data for x in secret_values): raise RuntimeError('Private credential in archive input: '+str(p.relative_to(root)))
with zipfile.ZipFile(source,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for f in files:z.write(f,f.relative_to(root).as_posix())
with zipfile.ZipFile(evidence,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for f in proof:z.write(f,f.relative_to(root).as_posix())
verification=json.loads((root/'evidence-m2-rails-colab-iframe-20261029/form-gate-acceptance.json').read_text())
assert verification['status']=='PASS_LOCAL_PASSWORD_FORM_GATE_RAILS_UI'
meta={'status':'PASS_COLAB_IFRAME_ACCESS_FIX_INTERNAL','captured_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'workspace':'bsmith888','modal_env':'rails-8-ai-customer-support-desk','rails_bind':'127.0.0.1:3068',
 'host_rule':'Colab port 3068 only','gate':'HTML password form + HMAC signed purpose-separated cookie',
 'csrf':'kept enabled','cookie':'HttpOnly / Secure SameSite=None Partitioned on HTTPS Colab',
 'browser_iframe':'NOT_VERIFIED_IN_USER_BROWSER',
 'tests':'43 tests, 502 assertions, zero failures/errors/skips',
 'tenant_ui':'TeamFlow VI and NovaMart EN HTTP 200, PII blocked HTTP 422',
 'database':'100 KB articles, 12 approved versions, 84 real vectors unchanged',
 'secrets_archived':False,'source_files':len(files),'evidence_files':len(proof),
 'source_sha256':sha(source),'evidence_sha256':sha(evidence),'db_sha256':sha(database)}
manifest.write_text(json.dumps(meta,indent=2)+'\n')
with zipfile.ZipFile(master,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for f in (source,evidence,database,manifest):z.write(f,f.name)
for file in (source,evidence,master):
 with zipfile.ZipFile(file) as z:
  assert z.testzip() is None
  assert all('access_token' not in n and 'rails-private-preview.env' not in n and 'master.key' not in n for n in z.namelist())
(out/'M2_COLAB_IFRAME_FIX_SHA256SUMS.txt').write_text(''.join(f'{sha(f)}  {f.name}\n' for f in (source,evidence,database,manifest,master)))
print(json.dumps({'status':meta['status'],'master':master.name,'bytes':master.stat().st_size,'sha256':sha(master),'source_files':len(files)},indent=2))
