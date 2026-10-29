#!/usr/bin/env python3
"""Prepare portable local backups. No external transfer or secret inclusion."""
import datetime
import hashlib
import json
import os
import re
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'checkpoints'
OUT.mkdir(exist_ok=True)
SOURCE_ZIP = OUT/'RAILS8_AI_SUPPORT_DESK_M2_PRIORITY_SOURCE_20261029.zip'
EVIDENCE_ZIP = OUT/'RAILS8_AI_SUPPORT_DESK_M2_PRIORITY_EVIDENCE_20261029.zip'
MASTER_ZIP = OUT/'RAILS8_AI_SUPPORT_DESK_M2_PRIORITY_BACKUP_20261029.zip'
DB_DUMP = OUT/'M2_PRIORITY_EDITORIAL_SYNTHETIC_DB_20261029.dump'
DIRS = ('app','bin','config','data','db','docs','modal_app','preview','review','script','test')
ROOT_FILES = ('Gemfile','Gemfile.lock','Rakefile','Dockerfile','compose.yaml','config.ru',
              'README_VI.md','README_EN.md','.gitignore','.dockerignore','.ruby-version')
EXCLUDED = {'.git','.bundle','vendor','bundle','tmp','log','node_modules','__pycache__','.cache','checkpoints'}

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

files=[]
for directory in DIRS:
  for p in (ROOT/directory).rglob('*'):
    if p.is_file() and not any(part in EXCLUDED or part.startswith('.env') for part in p.relative_to(ROOT).parts) and p.suffix not in ('.zip','.pyc','.log','.dump') and p.name not in ('master.key','credentials.yml.enc'):
      files.append(p)
files += [ROOT/f for f in ROOT_FILES if (ROOT/f).is_file()]
files=sorted(set(files))
# Detect token-like strings without printing secret values.
secret_patterns = [re.compile(rb'(?:ghp_|github_pat_|hf_|sk-|xox[baprs]-)[A-Za-z0-9_-]{24,}'),
                   re.compile(rb'-----BEGIN (?:RSA|OPENSSH|EC|PRIVATE) PRIVATE KEY-----')]
pg_secret=os.environ.get('PGPASSWORD','').encode()
for p in files:
  content=p.read_bytes()
  if any(pattern.search(content) for pattern in secret_patterns):
    raise RuntimeError('Sensitive token pattern detected in: '+str(p.relative_to(ROOT)))
  if len(pg_secret)>=10 and pg_secret in content:
    raise RuntimeError('DB credential detected in: '+str(p.relative_to(ROOT)))
with zipfile.ZipFile(SOURCE_ZIP,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=7) as z:
  for p in files:z.write(p,p.relative_to(ROOT).as_posix())

proofs=[]
for directory in ('evidence-m2-priority-20261029',
                  'evidence-m2-runtime-checkpoint-20261029',
                  'evidence-m1-final-checkpoint-20261029'):
  proofs += [p for p in (ROOT/directory).glob('*') if p.is_file()]
with zipfile.ZipFile(EVIDENCE_ZIP,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=7) as z:
  for p in sorted(proofs):z.write(p,p.relative_to(ROOT).as_posix())

assert DB_DUMP.exists() and DB_DUMP.stat().st_size>1000
manifest={
  'checkpoint':'M2_PRIORITY_EDITORIAL_BATCH_A',
  'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
  'source_files':len(files),'source_sha256':sha(SOURCE_ZIP),
  'evidence_files':len(proofs),'evidence_sha256':sha(EVIDENCE_ZIP),
  'synthetic_dev_pg_dump_sha256':sha(DB_DUMP),
  'm0_policies':'APPROVED_UNCHANGED',
  'm1':'UNCHANGED',
  'm2_original_v1':{'articles':100,'versions':200,'chunks':1400},
  'm2_editorial_v2':{'article_ids':6,'language_versions':12,'chunks':84,'status':'DRAFT_NOT_HUMAN_APPROVED'},
  'm2_postgres_expected':{'articles':100,'versions':212,'chunks':1484,'approved':0,'real_embeddings':0},
  'modal_gpu':'NOT_RUN', 'human_approval':'PENDING', 'cloud_backup':'NOT_UPLOADED',
  'notes':'Local Colab archive only; download to durable storage; never restore over existing DB.'
}
manifest_file=OUT/'M2_PRIORITY_EDITORIAL_BACKUP_MANIFEST.json'
manifest_file.write_text(json.dumps(manifest,indent=2)+'\n')
with zipfile.ZipFile(MASTER_ZIP,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=5) as z:
  for p in (SOURCE_ZIP,EVIDENCE_ZIP,DB_DUMP,manifest_file):z.write(p,p.name)
for p in (SOURCE_ZIP,EVIDENCE_ZIP,MASTER_ZIP):
  with zipfile.ZipFile(p) as z:
    assert z.testzip() is None
    assert not any(n.startswith('.env') or '/.env' in n or n.endswith('master.key') for n in z.namelist())
(OUT/'M2_PRIORITY_EDITORIAL_BACKUP_SHA256SUMS.txt').write_text(''.join(
  f'{sha(p)}  {p.name}\n' for p in (SOURCE_ZIP,EVIDENCE_ZIP,DB_DUMP,manifest_file,MASTER_ZIP)))
print(json.dumps({**manifest,'master_zip_name':MASTER_ZIP.name,
 'master_zip_size_bytes':MASTER_ZIP.stat().st_size,
 'master_zip_sha256':sha(MASTER_ZIP)},indent=2))
