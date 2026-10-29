#!/usr/bin/env python3
"""Produce a gold-label-free human validation queue for synthetic evidence.
NEVER write to Rails DB, dispatch business actions, or auto-approve responses."""
import json,hashlib,datetime
from pathlib import Path
root=Path(__file__).resolve().parents[1]
source=root/'review/m2_claim_level_manual32x2_lockbox_20261029.json'
ev=root/'evidence-m2-claim32x2-20261029'
result=ev/'claim32x2-live.jsonl'
summary=json.loads((ev/'claim32x2-report.json').read_text())
cases=json.loads(source.read_text())['cases']
records={r['id']:r for r in (json.loads(s) for s in result.read_text().splitlines())}
assert len(cases)==32 and len(records)==32
tasks=[]
for case in cases:
    row=records[case['id']]
    for c,estimate in zip(case['claims'],row['claims']):
        assert c['claim_id']==estimate['claim_id']
        tasks.append({
            'claim_id':c['claim_id'],
            'tenant':case['tenant'],'locale':case['locale'],
            'parent_question':case['question'],
            'atomic_claim':c['text'],
            'candidate_status':estimate['status'],
            'candidate_article':estimate['candidate_article'],
            'candidate_citations':estimate['citations'],
            'human_policy_supported':None,
            'human_supporting_citation':None,
            'human_decision_notes':None,
            'requires_case_data_or_escalation':None,
            'human_decision_status':'PENDING_MANUAL_VERIFICATION'
        })
assert len(tasks)==64
queue={
 'kind':'M2_CLAIM_LEVEL_BLIND_HUMAN_VALIDATION_QUEUE',
 'status':'PENDING_HUMAN_ASSESSMENT_NO_BUSINESS_WRITES',
 'generated_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'source_manifest_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
 'model_evidence_sha256':hashlib.sha256(result.read_bytes()).hexdigest(),
 'warning':'This file deliberately omits developer gold labels. Human auditors must independently inspect approved KB and exact cited article versions. Do not trust raw similarity as semantic support.',
 'tasks':tasks
}
dest=ev/'claim-level-blind-human-validation.json'
assert not dest.exists()
dest.write_text(json.dumps(queue,ensure_ascii=False,indent=2)+'\n')
assert all('gold' not in k for task in tasks for k in task)
print(json.dumps({'tasks':len(tasks),'sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),'destination':str(dest),'gold_leak_check':'PASS'}))
