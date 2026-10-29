#!/usr/bin/env python3
"""Bundle M2 proxy authentication + Rails UI source, evidence, and the unchanged 84-vector DB."""
import datetime
import hashlib
import json
import zipfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'checkpoints'
SRC=OUT/'RAILS8_M2_PROXY_UI_SOURCE_20261029.zip'
PROOF=OUT/'RAILS8_M2_PROXY_UI_EVIDENCE_20261029.zip'
DB=OUT/'M2_DUAL_QWEN3_4B_REAL_EMBEDDINGS_DB_20261029.dump'
MASTER=OUT/'RAILS8_M2_PROXY_UI_CHECKPOINT_20261029.zip'
MANIFEST=OUT/'M2_PROXY_UI_CHECKPOINT_MANIFEST.json'
sha=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
exclude={'__pycache__','.git','.bundle','vendor','bundle','node_modules','log','tmp','.cache','checkpoints'}
files=[]
for d in ('app','bin','config','data','db','docs','modal_app','preview','review','script','test'):
 for p in (ROOT/d).rglob('*'):
  rel=p.relative_to(ROOT)
  if p.is_file() and not any(part in exclude or part.startswith('.env') for part in rel.parts) and p.suffix not in ('.pyc','.zip','.log','.dump') and p.name not in ('master.key','credentials.yml.enc'):
   files.append(p)
files.extend(ROOT/name for name in ('README_VI.md','README_EN.md','Gemfile','Gemfile.lock','Rakefile','Dockerfile','config.ru','.dockerignore','.gitignore','.ruby-version') if (ROOT/name).is_file())
files=sorted(set(files))
# Cryptographic credentials live under ~/.config, never inside this source tree.
assert all('access_token' not in str(p) and 'proxy-token.json' not in str(p) for p in files)
with zipfile.ZipFile(SRC,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for p in files:z.write(p,p.relative_to(ROOT).as_posix())
proof_files=[]
for d in ('evidence-m2-proxy-ui-20261029','evidence-m2-dual-qwen3-4b-runtime','evidence-m2-dual-qwen3-4b-live'):
 proof_files += [p for p in (ROOT/d).glob('*') if p.is_file() and p.suffix not in ('.dump','.zip','.pyc')]
with zipfile.ZipFile(PROOF,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for p in sorted(set(proof_files)):z.write(p,p.relative_to(ROOT).as_posix())
assert DB.is_file() and DB.stat().st_size > 100_000
proof=json.loads((ROOT/'evidence-m2-proxy-ui-20261029/acceptance.json').read_text())
assert proof['status']=='PASS_PROXY_NEGATIVE_AND_UI_TESTS' and proof['stored_embeddings']==84
manifest={'checkpoint':'M2_PROXY_HARDENING_AND_BILINGUAL_RAILS_UI','created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'modal_environment':'rails-8-ai-customer-support-desk','modal_proxy_auth':'ON_BOTH_MODELS',
 'unauthenticated_http':'401_FOR_BOTH','credentials_in_archive':False,'proxy_token_created':False,
 'gpu_ui_status':'DISABLED_BY_DEFAULT_PENDING_OPERATOR_PROXY_TOKEN',
 'post_proxy_authenticated_positive_test':'NOT_RUN',
 'regression':'40 tests / 475 assertions / 0 failures',
 'database':'UNCHANGED_PREVIOUS_LIVE_CHECKPOINT_12_APPROVED_84_EMBEDDINGS',
 'source_file_count':len(files),'evidence_file_count':len(set(proof_files)),
 'source_sha256':sha(SRC),'evidence_sha256':sha(PROOF),'database_sha256':sha(DB)}
MANIFEST.write_text(json.dumps(manifest,indent=2)+'\n')
with zipfile.ZipFile(MASTER,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for p in (SRC,PROOF,DB,MANIFEST):z.write(p,p.name)
for archive in (SRC,PROOF,MASTER):
 with zipfile.ZipFile(archive) as z:
  assert z.testzip() is None
  assert all(not s.startswith('.env') and '/.env' not in s and 'proxy-token.json' not in s for s in z.namelist())
(OUT/'M2_PROXY_UI_CHECKPOINT_SHA256SUMS.txt').write_text(''.join(f'{sha(p)}  {p.name}\n' for p in (SRC,PROOF,DB,MANIFEST,MASTER)))
print(json.dumps({'name':MASTER.name,'bytes':MASTER.stat().st_size,'sha256':sha(MASTER),**manifest},indent=2))
