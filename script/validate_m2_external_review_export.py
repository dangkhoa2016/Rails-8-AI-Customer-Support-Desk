#!/usr/bin/env python3
"""Validate but NEVER impersonate a real external reviewer.
Offline verifier checks exported decision completeness and provenance,
not reviewer identity, policy interpretation or independent authorship.
Usage: python script/validate_m2_external_review_export.py /path/to/export.json
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import sys

BASE=Path(__file__).resolve().parents[1]
QUEUE=BASE/'evidence-m2-claim32x2-20261029/claim-level-blind-human-validation.json'
SNAP=BASE/'evidence-m2-claim64-provisional-audit-20261029/approved-kb-v2-readonly-snapshot.json'
VALID={'affirmative_policy','explicit_negative_policy','not_documented','uncertain_needs_second_reviewer'}
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def check_file(file:Path):
    payload=json.loads(file.read_text())
    queue=json.loads(QUEUE.read_text())
    snap=json.loads(SNAP.read_text())
    reviewer=payload.get('reviewer_id')
    assert isinstance(reviewer,str) and len(reviewer.strip())>=3,'Missing reviewer ID'
    assert payload.get('source_manifest_sha256')==queue['source_manifest_sha256'],'Wrong frozen manifest'
    assert payload.get('candidate_evidence_sha256')==queue['model_evidence_sha256'],'Wrong initial GPU evidence hash'
    assert payload.get('approved_snapshot_sha256')==sha(SNAP),'Wrong approved KB snapshot'
    decisions=payload['decisions'];assert isinstance(decisions,list) and len(decisions)==64,'Need all 64 decisions'
    source={t['claim_id']:t for t in queue['tasks']}
    approved={(a['tenant'],a['locale'],a['article_key']):a for a in snap['articles']}
    seen=set()
    pending=[]
    uncertain=[]
    for item in decisions:
        ident=item['claim_id']
        assert ident in source and ident not in seen,'Invalid/duplicated claim ID'
        seen.add(ident)
        old=source[ident]
        assert item['tenant']==old['tenant'] and item['locale']==old['locale'],'Tenant or locale mismatch'
        decision=item.get('reviewer_decision')
        if decision not in VALID:pending.append(ident);continue
        citation=item.get('evidence_article')
        quote=(item.get('evidence_quote_or_section') or '').strip()
        notes=(item.get('reviewer_notes') or '').strip()
        if decision in ('affirmative_policy','explicit_negative_policy'):
            assert citation,ident+': missing policy article'
            doc=approved.get((old['tenant'],old['locale'],citation))
            assert doc is not None,ident+': cross-tenant or nonexistent article citation'
            assert len(quote)>=20 and quote in doc['body'],ident+': quote must match exact approved v2 KB text'
            assert hashlib.sha256(doc['body'].encode()).hexdigest()==doc['body_sha256'],ident+': KB hash drift'
        elif decision=='not_documented':
            assert not citation,ident+': not documented must not claim a policy source'
            assert len(notes)>=20,ident+': explain search and uncertainty'
        else:
            uncertain.append(ident)
            assert len(notes)>=20,ident+': explain why independent arbitration needed'
    assert seen==set(source),'Mismatched claim set'
    return {'status':'STRUCTURE_AND_EXACT_CITATIONS_PASS_REVIEWER_IDENTITY_NOT_VERIFIED',
      'source_sha256':sha(file),'reviewer_id':reviewer,'items':len(decisions),
      'pending':pending,'uncertain':uncertain,
      'ready_for_second_reviewer_or_signoff':not pending and not uncertain,
      'does_not_prove':'authentic reviewer identity, independence, semantic correctness or authorization'}

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('export_json')
    args=parser.parse_args()
    try:
        print(json.dumps(check_file(Path(args.export_json)),ensure_ascii=False,indent=2))
    except (KeyError,ValueError,AssertionError,FileNotFoundError,TypeError) as e:
        print(json.dumps({'status':'REVIEW_EXPORT_INVALID','error':str(e)[:250]}))
        sys.exit(2)
