#!/usr/bin/env python3
"""Stdlib offline tests; deliberately NO model inference or external requests."""
import sys,unittest,json,copy
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'script'))
from m2_future_model_contracts import (
  validate_decomposition,validate_nli_observation,ContractRejected,
  SCHEMA,NLI_SCHEMA,canonical_sha)
class ContractTest(unittest.TestCase):
    def setUp(self):
        self.question="Invoice paid but plan not active; can you guarantee a fix within thirty minutes?"
        pivot=self.question.index(";")+2
        self.pivot=pivot
        self.payload={
          "schema":SCHEMA,"tenant":"teamflow-cloud","locale":"en",
          "question_sha256":canonical_sha(self.question),
          "claims":[
             {"id":"c1","source_start":0,"source_end":pivot,
              "source_excerpt":self.question[:pivot],
              "hypothesis":"The invoice is paid and the subscription activation has not succeeded.",
              "intent":"case_specific_fact","needs_case_data":True},
             {"id":"c2","source_start":pivot,"source_end":len(self.question),
              "source_excerpt":self.question[pivot:],
              "hypothesis":"Support guarantees the activation issue is resolved in thirty minutes.",
              "intent":"requested_action","needs_case_data":False}
          ],"unresolved":[]
        }
        approved=json.loads((ROOT/'evidence-m2-claim64-provisional-audit-20261029'/
            'approved-kb-v2-readonly-snapshot.json').read_text())['articles']
        a=next(x for x in approved if x['tenant']=='teamflow-cloud' and
            x['locale']=='en' and x['article_key']=='TF-KB-012')
        self.approved=a
        self.premise=a['body'][0:600]
        self.nli={
          "schema":NLI_SCHEMA,"tenant":"teamflow-cloud","locale":"en",
          "article_key":"TF-KB-012","article_version_id":a['article_version_id'],
          "article_body_sha256":a['body_sha256'],"premise_excerpt":self.premise,
          "hypothesis":"Activation alone guarantees a fix within thirty minutes.",
          "model_id":"OFFLINE_MOCK_NLI","model_revision":"a"*40,
          "scores":{"entailment":0.02,"neutral":0.08,"contradiction":0.90},
          "predicted_label":"contradiction"
        }
    def validate_claims(self,obj=None):
        return validate_decomposition(obj or self.payload,original_question=self.question,
          locale='en',tenant='teamflow-cloud')
    def validate_nli(self,obj=None):
        return validate_nli_observation(obj or self.nli,expected_tenant='teamflow-cloud',
           expected_locale='en',expected_article_key='TF-KB-012',
           expected_version_id=self.approved['article_version_id'],
           expected_full_body_sha256=self.approved['body_sha256'],
           approved_body=self.approved['body'])
    def test_good_manual_fixtures_are_not_misreported_as_inference(self):
        self.assertEqual(self.validate_claims()['claim_count'],2)
        self.assertFalse(self.validate_claims()['semantic_fidelity_proved'])
        self.assertTrue(self.validate_nli()['scores_are_uncalibrated'])
        self.assertFalse(self.validate_nli()['supports_autonomous_business_action'])
    def test_fabricated_quote_rejected(self):
        v=copy.deepcopy(self.payload);v['claims'][0]['source_excerpt']="fabricated quote"
        with self.assertRaises(ContractRejected):self.validate_claims(v)
    def test_missing_intent_text_rejected(self):
        v=copy.deepcopy(self.payload);v['claims']=v['claims'][:1]
        with self.assertRaises(ContractRejected):self.validate_claims(v)
    def test_bad_tenant_and_hash_rejected(self):
        for field,value in [('tenant','novamart-store'),('question_sha256','a'*64)]:
            v=copy.deepcopy(self.payload);v[field]=value
            with self.assertRaises(ContractRejected):self.validate_claims(v)
    def test_unexpected_json_field_rejected(self):
        v=copy.deepcopy(self.payload);v['business_action']='approve_refund'
        with self.assertRaises(ContractRejected):self.validate_claims(v)
    def test_pii_rejected(self):
        question="Send this refund to customer@example.com before tomorrow please."
        with self.assertRaises(ContractRejected):
            validate_decomposition(self.payload,original_question=question,
              locale='en',tenant='teamflow-cloud')
    def test_forged_kb_evidence_rejected(self):
        v=copy.deepcopy(self.nli);v['premise_excerpt']="This article guarantees an automatic refund at once."
        with self.assertRaises(ContractRejected):self.validate_nli(v)
    def test_wrong_kb_version_or_tenant_rejected(self):
        for field,value in [('article_version_id',888888),('tenant','novamart-store'),
            ('article_body_sha256','b'*64),('article_key','NM-KB-020')]:
            v=copy.deepcopy(self.nli);v[field]=value
            with self.assertRaises(ContractRejected):self.validate_nli(v)
    def test_invalid_probability_triples_rejected(self):
        for scores in [
            {'entailment':0.1,'neutral':0.1,'contradiction':0.1},
            {'entailment':0.1,'neutral':float('nan'),'contradiction':0.9},
            {'entailment':-0.1,'neutral':0.2,'contradiction':0.9}
        ]:
            v=copy.deepcopy(self.nli);v['scores']=scores
            with self.assertRaises(ContractRejected):self.validate_nli(v)
    def test_wrong_predicted_label_rejected(self):
        v=copy.deepcopy(self.nli);v['predicted_label']='entailment'
        with self.assertRaises(ContractRejected):self.validate_nli(v)
if __name__=='__main__':
    unittest.main(verbosity=2)
