#!/usr/bin/env python3
"""Reproducible source/offline-only evidence. Never represents Rails/DB as executed."""
from pathlib import Path
import subprocess,sys,json,hashlib,datetime,shutil
root=Path(__file__).resolve().parent.parent
out=root/'evidence/m2';out.mkdir(exist_ok=True,parents=True)
commands=[
 ('01_blueprint_static',['python3','script/validate_approved_blueprint.py']),
 ('02_m2_generate',['python3','script/generate_m2_knowledge.py']),
 ('03_m2_verify',['python3','script/verify_m2_knowledge.py','--report','evidence/m2/knowledge-offline-validation.json']),
 ('04_m2_negative_tests',['python3','-m','unittest','discover','-s','test','-p','test_m2_knowledge.py','-v']),
 ('05_m1_python_regression',['python3','-m','unittest','discover','-s','test','-p','test_m1_dataset.py','-v']),
 ('06_m1_ruby_policy_regression',['ruby','test/policy_rules_test.rb']),
 ('07_rails_source_validation',['python3','script/offline_scaffold_check.py']),
 ('08_erb_syntax',['ruby','script/check_erb_syntax.rb']),
 ('09_preview_render',['python3','script/render_m2_preview.py']),
 ('10_review_manifest',['python3','script/export_m2_review_manifest.py']),
]
results={}
for id,cmd in commands:
 start=datetime.datetime.now(datetime.timezone.utc)
 p=subprocess.run(cmd,cwd=root,text=True,capture_output=True)
 end=datetime.datetime.now(datetime.timezone.utc)
 (out/(id+'.stdout.log')).write_text(p.stdout)
 (out/(id+'.stderr.log')).write_text(p.stderr)
 (out/(id+'.command.json')).write_text(json.dumps(cmd))
 results[id]={'command':cmd,'exit_code':p.returncode,'started_utc':start.isoformat(),'ended_utc':end.isoformat()}
 print(id,'PASS' if p.returncode==0 else 'FAIL')
 if p.returncode: print(p.stderr[-1000:]); break
# Re-render and compare two independently generated payload bytes.
source=(root/'data/m2/knowledge_drafts.json').read_bytes()
(tmp:=out/'regenerated-knowledge.json').unlink(missing_ok=True)
p=subprocess.run(['python3','script/generate_m2_knowledge.py','--output',str(tmp)],cwd=root,text=True,capture_output=True)
repro=(p.returncode==0 and tmp.read_bytes()==source)
tmp.unlink(missing_ok=True)
print('11_byte_identical_regeneration', 'PASS' if repro else 'FAIL')
results['11_byte_identical_regeneration']={'command':['python3','script/generate_m2_knowledge.py','--output','<temporary>'],
 'exit_code':0 if repro else 1,'dataset_sha256':hashlib.sha256(source).hexdigest()}
# Count real existing files, not projected database records.
payload=json.loads(source)
versions=[v for a in payload['articles'] for v in a['versions']]
status='PASS_OFFLINE_ONLY' if len(results)==11 and all(x['exit_code']==0 for x in results.values()) else 'FAIL'
manifest={'milestone':'M2','source_policy_version':'1.0.0','result':status,
 'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'artifact_scope':{'synthetic_kb_articles_generated':len(payload['articles']),
                   'language_versions_draft':len(versions),'chunks_unembedded':sum(len(v['chunks']) for v in versions),
                   'approved_versions':0},
 'tests':results,
 'runtime_rails_boot':'NOT_RUN','postgresql_migrations':'NOT_RUN','postgresql_seed':'NOT_RUN',
 'http_integration_tests':'NOT_RUN','editorial_article_approval':'PENDING_HUMAN_REVIEW',
 'modal_endpoint':'NOT_CONFIGURED','modal_embedding_inference':'NOT_RUN',
 'vector_index':'NOT_CREATED','semantic_retrieval_benchmark':'NOT_RUN',
 'lexical_search':'SOURCE_ONLY_NOT_RUNTIME_VERIFIED',
 'source_blueprint_sha256':payload['source_blueprint_sha256'],
 'author_notes_sha256':payload['author_notes_sha256'],
 'kb_dataset_sha256':hashlib.sha256(source).hexdigest(),
 'warning':'This does not establish Rails DB or Modal acceptance. All articles are unapproved editorial drafts.'}
(out/'m2-offline-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
files=sorted(x for x in out.rglob('*') if x.is_file() and x.name!='checksums.sha256')
(out/'checksums.sha256').write_text(''.join(hashlib.sha256(f.read_bytes()).hexdigest()+'  '+str(f.relative_to(out))+'\n' for f in files))
print('FINAL',status)
if status!='PASS_OFFLINE_ONLY': sys.exit(1)
