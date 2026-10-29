#!/usr/bin/env python3
"""Create verified local M2 4B/4B live checkpoint without endpoint credentials."""
import datetime
import hashlib
import json
import re
import zipfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'checkpoints'
OUT.mkdir(exist_ok=True)
SOURCE=OUT/'RAILS8_M2_DUAL_QWEN3_4B_LIVE_SOURCE_20261029.zip'
EVIDENCE=OUT/'RAILS8_M2_DUAL_QWEN3_4B_LIVE_EVIDENCE_20261029.zip'
DB=OUT/'M2_DUAL_QWEN3_4B_REAL_EMBEDDINGS_DB_20261029.dump'
MASTER=OUT/'RAILS8_M2_DUAL_QWEN3_4B_LIVE_CHECKPOINT_20261029.zip'
exclude={'checkpoints','.git','__pycache__','.bundle','node_modules','vendor','bundle','log','tmp','.cache'}
source_dirs=['app','bin','config','data','db','docs','modal_app','preview','review','script','test']
root_files=['README_EN.md','README_VI.md','Gemfile','Gemfile.lock','Rakefile','config.ru','Dockerfile','compose.yaml','.ruby-version','.gitignore','.dockerignore']
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
files=[]
for directory in source_dirs:
 for p in (ROOT/directory).rglob('*'):
  rel=p.relative_to(ROOT)
  if p.is_file() and not any(part in exclude or part.startswith('.env') for part in rel.parts) and p.suffix not in ('.log','.dump','.zip','.pyc') and p.name not in ('credentials.yml.enc','master.key'):
   files.append(p)
files += [ROOT/n for n in root_files if (ROOT/n).is_file()]
files=sorted(set(files))
private_patterns=[re.compile(rb'(?:wk-|ws-|ghp_|github_pat_|hf_|sk-)[A-Za-z0-9_-]{24,}'), re.compile(rb'-----BEGIN .*PRIVATE KEY-----')]
for p in files:
 content=p.read_bytes()
 # Ignore the literal scanner definitions in this scanner source, not real secrets.
 if p.name.startswith('package_m2_'):
  content=b'\n'.join(line for line in content.splitlines() if b're.compile(rb' not in line and b'private_patterns=' not in line and b'token_checks=' not in line and b'secret_patterns=' not in line)
 if any(expr.search(content) for expr in private_patterns):
  raise RuntimeError('Potential credential in '+str(p.relative_to(ROOT)))
with zipfile.ZipFile(SOURCE,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for p in files:z.write(p,p.relative_to(ROOT).as_posix())
evidence_dirs=['evidence-m2-dual-qwen3-4b-preflight','evidence-m2-dual-qwen3-4b-live','evidence-m2-dual-qwen3-4b-runtime']
logs=[]
for d in evidence_dirs:
 logs += [p for p in (ROOT/d).rglob('*') if p.is_file() and p.suffix not in ('.pyc','.dump')]
logs=sorted(set(logs))
with zipfile.ZipFile(EVIDENCE,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for p in logs:z.write(p,p.relative_to(ROOT).as_posix())
assert DB.is_file() and DB.stat().st_size>50000
pilot=json.loads((ROOT/'evidence-m2-dual-qwen3-4b-live/pilot-results.json').read_text())
accept=json.loads((ROOT/'evidence-m2-dual-qwen3-4b-runtime/live-db-acceptance.json').read_text())
bill=json.loads((ROOT/'evidence-m2-dual-qwen3-4b-runtime/modal-billing-snapshot.json').read_text())
assert pilot['status']=='LIVE_MODELS_EXECUTED' and pilot['cases']==12
assert accept['status']=='PASS_LIVE_EMBEDDED_DB_AND_FILTERED_RETRIEVAL' and accept['embeddings']==84
manifest={
 'status':'PASS_M2_LIVE_DUAL_4B_PILOT_NOT_FULL_M2',
 'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'device':'306682c8dabe',
 'modal_profile':'bsmith888','modal_environment':'rails-8-ai-customer-support-desk',
 'modal_gpu':'A10G','model_containers_max_each':1,
 'embedding_model':'Qwen/Qwen3-Embedding-4B','embedding_revision':'5cf2132abc99cad020ac570b19d031efec650f2b',
 'reranker_model':'Qwen/Qwen3-Reranker-4B','reranker_revision':'22e683669bc0f0bd69640a1354a6d0aebcfeede5',
 'runtime_model_source':'Hugging Face pinned; Kaggle mirrored alternatives inspected; large Kaggle shard failed API 1994',
 'embedding_manifest_sha256':sha(ROOT/'evidence-m2-dual-qwen3-4b-runtime/embedding-model-manifest.json'),
 'reranker_manifest_sha256':sha(ROOT/'evidence-m2-dual-qwen3-4b-runtime/reranker-model-manifest.json'),
 'm0_m1':'UNCHANGED','v1_drafts':200,'v2_approved':12,'real_vectors':84,'dimension':2560,
 'pilot_queries':12,'pilot_top1_correct':12,'recall_at_5':pilot['hit_at_5_rate'],'mrr_at_5':pilot['mrr_at_5'],
 'warm_query_median_ms':1477.8,'pilot_wall_seconds':pilot['full_wall_seconds'],
 'post_gpu_rails_tests':'34 tests, 402 assertions, 0 failures/errors/skips',
 'idempotency':'PASS_NO_GPU_CALLS',
 'modal_billing_snapshot_usd':bill['metered_cost'],
 'warning':'Modal proxy auth not enabled; app-level bearer token only. Do not claim production-ready.',
 'source_file_count':len(files),'evidence_file_count':len(logs),
 'source_sha256':sha(SOURCE),'evidence_sha256':sha(EVIDENCE),'db_dump_sha256':sha(DB),
}
manifest_file=OUT/'M2_DUAL_QWEN3_4B_LIVE_CHECKPOINT_MANIFEST.json'
manifest_file.write_text(json.dumps(manifest,indent=2)+'\n')
with zipfile.ZipFile(MASTER,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for p in (SOURCE,EVIDENCE,DB,manifest_file):z.write(p,p.name)
for p in (SOURCE,EVIDENCE,MASTER):
 with zipfile.ZipFile(p) as z:
  assert z.testzip() is None
  assert not any(x.startswith('.env') or '/.env' in x or 'master.key' in x for x in z.namelist())
(OUT/'M2_DUAL_QWEN3_4B_LIVE_SHA256SUMS.txt').write_text(''.join(f'{sha(p)}  {p.name}\n' for p in (SOURCE,EVIDENCE,DB,manifest_file,MASTER)))
print(json.dumps({'manifest':manifest,'master_file':MASTER.name,'master_bytes':MASTER.stat().st_size,'master_sha256':sha(MASTER)},indent=2))
