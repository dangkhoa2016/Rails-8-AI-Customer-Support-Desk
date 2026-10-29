#!/usr/bin/env python3
"""Bundle verified offline M2 4B/4B source + tests + approved synthetic DB."""
import datetime
import hashlib
import json
import os
import re
import zipfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'checkpoints'
OUT.mkdir(exist_ok=True)
source_zip=OUT/'RAILS8_M2_DUAL_QWEN3_4B_SOURCE_20261029.zip'
evidence_zip=OUT/'RAILS8_M2_DUAL_QWEN3_4B_EVIDENCE_20261029.zip'
master_zip=OUT/'RAILS8_M2_DUAL_QWEN3_4B_CHECKPOINT_20261029.zip'
db_dump=OUT/'M2_DUAL_QWEN3_4B_APPROVED_SYNTHETIC_DB_20261029.dump'
exclude={'.git','.bundle','vendor','bundle','tmp','log','node_modules','__pycache__','.cache','checkpoints'}
roots=('app','bin','config','data','db','docs','modal_app','preview','review','script','test')
top=('Gemfile','Gemfile.lock','Rakefile','Dockerfile','compose.yaml','config.ru','README_EN.md','README_VI.md','.ruby-version','.gitignore','.dockerignore')
sha=lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
files=[]
for folder in roots:
 for f in (ROOT/folder).rglob('*'):
  if not f.is_file():continue
  rel=f.relative_to(ROOT)
  if any(part in exclude or part.startswith('.env') for part in rel.parts):continue
  if f.suffix in ('.zip','.pyc','.log','.dump'):continue
  if f.name in ('credentials.yml.enc','master.key'):continue
  files.append(f)
files.extend(ROOT/n for n in top if (ROOT/n).exists())
files=sorted(set(files))
token_checks=[re.compile(rb'(?:ghp_|github_pat_|hf_|sk-|xox[baprs]-)[A-Za-z0-9_-]{24,}'),re.compile(rb'-----BEGIN .*PRIVATE KEY-----')]
for f in files:
 contents=f.read_bytes()
 # Exclude only this scanner's literal regex-definition line from self-scanning.
 if f.name in ('package_m2_dual4b_checkpoint.py', 'package_m2_priority_backup.py'):
  contents=b'\n'.join(line for line in contents.splitlines() if b're.compile(rb' not in line and b'token_checks=' not in line and b'secret_patterns' not in line)
 if any(p.search(contents) for p in token_checks):raise RuntimeError('Sensitive token pattern found in '+str(f.relative_to(ROOT)))
 pw=os.environ.get('PGPASSWORD','').encode()
 if len(pw)>10 and pw in contents:raise RuntimeError('Database secret found in '+str(f.relative_to(ROOT)))
with zipfile.ZipFile(source_zip,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for f in files:z.write(f,f.relative_to(ROOT).as_posix())
proof=[]
for folder in ['evidence-m2-dual-qwen3-4b-preflight','evidence-m2-dual-qwen3-4b-preflight']:
 proof.extend(f for f in (ROOT/folder).glob('*') if f.is_file())
proof=sorted(set(proof))
lexical=ROOT/'evidence-m2-dual-qwen3-4b-preflight/lexical-baseline.json'
if lexical.exists():proof.append(lexical)
with zipfile.ZipFile(evidence_zip,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for f in sorted(set(proof)):z.write(f,f.relative_to(ROOT).as_posix())
assert db_dump.is_file() and db_dump.stat().st_size>50000
manifest={
 'checkpoint':'M2_EDITORIAL_APPROVED_AND_QWEN3_DUAL_4B_SOURCE_ONLY',
 'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'source_files':len(files),'source_sha256':sha(source_zip),'evidence_sha256':sha(evidence_zip),
 'synthetic_dev_pg_dump_sha256':sha(db_dump),
 'm0_policy_version':'1.0.0','m1':'UNCHANGED','v1_drafts':200,'v2_approved':12,'approved_chunks':84,
 'embedding_model':'Qwen/Qwen3-Embedding-4B','embedding_revision':'5cf2132abc99cad020ac570b19d031efec650f2b',
 'reranker_model':'Qwen/Qwen3-Reranker-4B','reranker_revision':'22e683669bc0f0bd69640a1354a6d0aebcfeede5',
 'vector_dimensions':2560,'gpu_inference':'NOT_RUN','real_embeddings':0,
 'test_status':'PASS_9_STAGES_PREFLIGHT_SYNTHETIC_VECTORS',
 'auth_status':'MODAL_NOT_AUTHENTICATED','public_rails':'NOT_EXPOSED',
 'cloud_backup':'NOT_UPLOADED',
 'notes':'Local Colab backup only, not durable cloud storage. Never restore over running DB.'}
mfile=OUT/'M2_DUAL_QWEN3_4B_CHECKPOINT_MANIFEST.json';mfile.write_text(json.dumps(manifest,indent=2)+'\n')
with zipfile.ZipFile(master_zip,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for f in (source_zip,evidence_zip,db_dump,mfile):z.write(f,f.name)
for f in (source_zip,evidence_zip,master_zip):
 with zipfile.ZipFile(f) as z:
  assert z.testzip() is None
  assert not any('/.env' in n or n.startswith('.env') or 'master.key' in n for n in z.namelist())
(OUT/'M2_DUAL_QWEN3_4B_CHECKPOINT_SHA256SUMS.txt').write_text(''.join(f'{sha(p)}  {p.name}\n' for p in (source_zip,evidence_zip,db_dump,mfile,master_zip)))
print(json.dumps({**manifest,'master_zip':master_zip.name,'master_sha256':sha(master_zip),'master_bytes':master_zip.stat().st_size},indent=2))
