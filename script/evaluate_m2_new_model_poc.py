#!/usr/bin/env python3
"""Evaluate an isolated GPU POC without changing frozen inputs or inference output."""
import hashlib
import json
from pathlib import Path
import statistics
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"script"))
from m2_future_model_contracts import validate_decomposition,validate_nli_observation,ContractRejected

D=ROOT/"evidence-m2-new-modal-model-poc-20261029"
M=ROOT/"review/m2_new_models_isolated_poc_development_20261029.json"
P=ROOT/"review/m2_new_models_isolated_poc_nli_premises_20261029.json"
SNAP=ROOT/"evidence-m2-claim64-provisional-audit-20261029/approved-kb-v2-readonly-snapshot.json"
EXPECTED={
 "manifest":"bab124fdab56ed5b0bc1d36b5208a240d4ddcca0bed6b336914df0158e50508a",
 "premises":"419e2e6c7547c579f410c99587a9449d52e259115086cd84b77a9fb4bb73874e"
}
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(M)==EXPECTED['manifest'] and sha(P)==EXPECTED['premises']
dev=json.loads(M.read_text())
pairs=json.loads(P.read_text())
kb=json.loads(SNAP.read_text())
kb_index={(r['tenant'],r['locale'],r['article_key']):r for r in kb['articles']}
out={
 'kind':'M2_ISOLATED_MODAL_DECOMP_NLI_POC_EVALUATION',
 'status':'DEVELOPMENT_POC_NEVER_RELEASE_NOT_HUMAN_ADJUDICATED',
 'manifest_sha256':sha(M),'premises_sha256':sha(P),
 'question_count':8,'nli_pair_count':12,
 'independent_human_gold':'PENDING_NOT_RUN',
 'decomposition':{'execution_status':'NOT_RUN'},
 'nli':{'execution_status':'NOT_RUN'}
}

def question_eval():
    path=D/'decomposition-live.json'
    if not path.exists():
        return {'execution_status':'FAILED_OR_NOT_RUN','error_report':(D/'decomposition-failure.json').exists()}
    data=json.loads(path.read_text())
    assert data['model_id']==dev['model_pins']['decomposition']['id']
    assert data['model_revision']==dev['model_pins']['decomposition']['revision']
    assert len(data['results'])==8
    by_id={r['id']:r for r in dev['decomposition_cases']}
    valid=0
    evaluations=[]
    times=[]
    for item in data['results']:
        source=by_id[item['id']]
        assert item['tenant']==source['tenant'] and item['locale']==source['locale']
        assert item['question_sha256']==hashlib.sha256(source['question'].encode()).hexdigest()
        is_valid=False; reason=None; claim_count=None
        if not isinstance(item['parsed_model_output'], dict):
            reason='INVALID_JSON_OR_WRONG_ROOT_TYPE_NO_REPAIR'
        else:
            wrapped={
                'schema':'rails8.m2.claim_decomposition.v1',
                'tenant':source['tenant'],'locale':source['locale'],
                'question_sha256':item['question_sha256'],
                'claims':item['parsed_model_output'].get('claims'),
                'unresolved':item['parsed_model_output'].get('unresolved')
            }
            if set(item['parsed_model_output'])!={'claims','unresolved'}:
                reason='MODEL_JSON_UNEXPECTED_FIELDS'
            else:
                try:
                    check=validate_decomposition(wrapped,
                      original_question=source['question'],
                      locale=source['locale'],tenant=source['tenant'])
                    is_valid=check['valid'];claim_count=check['claim_count']
                except (ContractRejected,TypeError,KeyError) as e:
                    reason=str(e)[:200]
        valid+=int(is_valid)
        times.append(item['generation_seconds'])
        evaluations.append({'id':item['id'],'tenant':item['tenant'],
          'locale':item['locale'],'json_parsed':item['parsed_model_output'] is not None,
          'schema_source_spans_valid':is_valid,'failure_reason':reason,'claim_count':claim_count,
          'generation_seconds':item['generation_seconds']})
    return {'execution_status':'COMPLETE','valid_schema_source_spans':valid,
      'total':len(evaluations),'strict_pass_fraction':valid/len(evaluations),
      'inference_generation_seconds_total':round(sum(times),3),
      'generation_seconds_p50':round(statistics.median(times),3),
      'model_loading_seconds':data['model_loading_seconds'],
      'gpu':data['gpu'],'gpu_peak_allocated_bytes':data['gpu_peak_allocated_bytes'],
      'remote_invocation_wall_seconds':data['remote_invocation_wall_seconds'],
      'raw_results_sha256':sha(path),
      'semantic_fidelity_verified':False,
      'cases':evaluations}

def nli_eval():
    path=D/'nli-live.json'
    if not path.exists():
        return {'execution_status':'FAILED_OR_NOT_RUN','error_report':(D/'nli-failure.json').exists()}
    data=json.loads(path.read_text())
    if data.get('status')!='MODEL_INFERENCE_COMPLETE':
        return {'execution_status':data.get('status','NO_VALID_NLI'), 'raw_results_sha256':sha(path)}
    assert data['model_id']==dev['model_pins']['nli']['id']
    assert data['model_revision']==dev['model_pins']['nli']['revision']
    assert len(data['results'])==12
    by_id={r['id']:r for r in pairs['cases']}
    matrix={v:{p:0 for p in ('entailment','neutral','contradiction')}
            for v in ('entailment','neutral','contradiction')}
    outcomes=[]
    valid=0
    for item in data['results']:
        expected=by_id[item['id']]
        assert item['hypothesis']==expected['hypothesis']
        article=kb_index[(item['tenant'],item['locale'],item['article_key'])]
        assert expected['premise_excerpt']==item['premise_excerpt']
        assert item['premise_excerpt'] in article['body']
        try:
            contract={k:v for k,v in item.items() if k not in ('id','latency_seconds','input_tokens')}
            contract['schema']='rails8.m2.nli_candidate.v1'
            validate_nli_observation(contract,
              expected_tenant=expected['tenant'],expected_locale=expected['locale'],
              expected_article_key=expected['article_key'],
              expected_version_id=expected['article_version_id'],
              expected_full_body_sha256=article['body_sha256'],
              approved_body=article['body'])
            valid+=1
        except ContractRejected as e:
            raise RuntimeError(f"source integrity violation in case {item['id']}: {e}") from e
        true=expected['gold_label'];pred=item['predicted_label']
        matrix[true][pred]+=1
        outcomes.append({'id':item['id'],'tenant':item['tenant'],
          'locale':item['locale'],'developer_label':true,
          'predicted_label':pred,'matches_developer_label':true==pred,
          'scores_uncalibrated':item['scores'],'latency_seconds':item['latency_seconds']})
    correct=sum(x['matches_developer_label'] for x in outcomes)
    return {'execution_status':'COMPLETE','source_integrity_valid':valid,
      'total':len(outcomes),'matched_developer_labels':correct,
      'accuracy_vs_unreviewed_developer_labels':round(correct/len(outcomes),4),
      'confusion_matrix_gold_rows_prediction_columns':matrix,
      'gpu':data['gpu'],'precision':data['precision'],'id2label':data['id2label'],
      'gpu_peak_allocated_bytes':data['gpu_peak_allocated_bytes'],
      'model_loading_seconds':data['model_loading_seconds'],
      'remote_invocation_wall_seconds':data['remote_invocation_wall_seconds'],
      'raw_results_sha256':sha(path),'actual_model_probabilities_calibrated':False,
      'cases':outcomes}
out['decomposition']=question_eval()
out['nli']=nli_eval()
out['assessment']='RESEARCH_ONLY_NO_RELEASE_HUMAN_APPROVAL_REQUIRED'
outpath=D/'poc-evaluation.json'
assert not outpath.exists(),'Do not overwrite evaluation'
outpath.write_text(json.dumps(out,indent=2,ensure_ascii=False)+'\n')
print(json.dumps({
 'evaluation_sha256':sha(outpath),
 'decomposition':{k:v for k,v in out['decomposition'].items() if k!='cases'},
 'nli':{k:v for k,v in out['nli'].items() if k!='cases'},
 'human':'NOT_RUN', 'release':'BLOCKED'
},indent=2,ensure_ascii=False))
