#!/usr/bin/env python3
"""Freeze a pilot scope verifier policy from the completed, labeled diagnostic.
Calibration uses 36 discovery cases. The 24 multi-intent cases are eval ONLY."""
import hashlib,json,pathlib,datetime
root=pathlib.Path(__file__).resolve().parents[1]
ev=root/'evidence-m2-answerability-20261029'
pilot=ev/'scope-probe-pilot.jsonl'
holdout=ev/'multi-intent-scope-probe.jsonl'
contracts=root/'review/m2_answerability_scope_probes_20261029.json'
rows=[json.loads(x) for x in pilot.read_text().splitlines()]
h=[json.loads(x) for x in holdout.read_text().splitlines()]
assert len(rows)==36 and len(h)==24
base=7.421875
# Calibrate only on near-domain negatives; cases with low relevance never reach this stage.
negative=[r['delta'] for r in rows if r['label']=='unsupported' and r['initial_top1_logit']>=5.0]
positive=[r['delta'] for r in rows if r['label']=='supported' and r['initial_top1_logit']>=base]
assert len(negative)>=2 and len(positive)>=12
max_n=max(negative);min_p=min(positive)
assert min_p>max_n, (min_p,max_n)
cutoff=(min_p+max_n)/2.0
def scores(xs):
    a=lambda x:x['combined_accepted'] if 'combined_accepted' in x else (x['initial_top1_logit']>=base and x['delta']>=cutoff)
    p=lambda x:x.get('gold_support',x.get('label')=='supported')
    return {
      'positive':sum(bool(p(x)) for x in xs),
      'negative':sum(not p(x) for x in xs),
      'true_positive':sum(bool(p(x)) and a(x) for x in xs),
      'false_positive':sum(not p(x) and a(x) for x in xs),
      'false_negative':sum(bool(p(x)) and not a(x) for x in xs),
      'true_negative':sum(not p(x) and not a(x) for x in xs)
    }
train=scores(rows);test=scores(h)
assert test['false_positive']==0 and test['true_positive']==5
assert test['positive']==6 and test['negative']==18
# Use the baseline existing relevance config and its pinned document fingerprint.
relevance=json.loads((root/'review/m2_relevance_gate_pilot_20261029.json').read_text())
digest=lambda p:hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
out={
 'id':'M2_SCOPE_CONTRAST_PILOT_V1',
 'status':'EXPERIMENTAL_HUMAN_ASSIST_ONLY_NOT_ENTAILMENT',
 'method':'same-article same-locale Reranker-4B scores on 4 supported + 4 unsupported curated questions, margin=best-supported-minus-best-unsupported',
 'threshold_margin':cutoff,
 'calibration_min_supported_margin':min_p,
 'calibration_max_near_domain_unsupported_margin':max_n,
 'relevance_threshold':base,
 'probe_manifest_sha256':digest(contracts),
 'scope_probe_pilot_sha256':digest(pilot),
 'multi_intent_holdout_manifest_sha256':digest(root/'review/m2_answerability_multi_intent_lockbox_20261029.json'),
 'multi_intent_holdout_retrieval_sha256':digest(ev/'multi-intent-retrieval-v2.jsonl'),
 'multi_intent_holdout_scores_sha256':digest(holdout),
 'relevance_policy_sha256':digest(root/'review/m2_relevance_gate_pilot_20261029.json'),
 'approved_versions_sha256':relevance['approved_versions_sha256'],
 'approved_version_count':relevance['approved_version_count'],
 'embedding_count':relevance['embedding_count'],
 'organization_policy_versions':relevance['organization_policy_versions'],
 'embedding_model':relevance['embedding_model'],
 'embedding_revision':relevance['embedding_revision'],
 'reranker_model':relevance['reranker_model'],
 'reranker_revision':relevance['reranker_revision'],
 'max_extra_reranker_calls_per_query':1,
 'required_probe_count':8,
 'calibration_metrics':train,
 'held_out_multi_intent_metrics':test,
 'limitations':'Prompt similarity is NOT proof of semantic entailment. A narrow synthetic pilot cannot guarantee no unsupported answers; always require human review.',
 'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat()
}
target=root/'review/m2_answerability_scope_policy_pilot_20261029.json'
assert not target.exists()
target.write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(out,ensure_ascii=False,indent=2))
