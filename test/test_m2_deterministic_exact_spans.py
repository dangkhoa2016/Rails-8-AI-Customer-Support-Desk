#!/usr/bin/env python3
"""Unit tests against generic source spans; NO GPU and NO model outputs."""
from pathlib import Path
import copy,sys,unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"script"))
from m2_deterministic_exact_spans import recover,SpanRejected

class ExactSpanRecoveryTest(unittest.TestCase):
    def setUp(self):
        self.question="Gói chưa được kích hoạt; có được hứa xử lý trước thứ Sáu không?"
        first,second=self.question.split("; ")
        self.response={"claims":[
            {"id":"c1","excerpt":first,"intent":"case_specific_fact","needs_case_data":True},
            {"id":"c2","excerpt":second,"intent":"requested_action","needs_case_data":False}],
            "unresolved":[]}
    def resolve(self,reply=None,query=None):
        return recover(query or self.question,reply if reply is not None else self.response,
                       tenant="teamflow-cloud",locale="vi")
    def test_deterministic_unicode_exact_offsets(self):
        r=self.resolve()
        self.assertEqual(r['claim_count'],2)
        self.assertEqual(r['claims'][0]['source_start'],0)
        for c in r['claims']:
            self.assertEqual(self.question[c['source_start']:c['source_end']],c['source_excerpt'])
        self.assertFalse(r['semantic_fidelity_verified'])
        self.assertFalse(r['business_actions_authorized'])
        self.assertTrue(r['human_review_required'])
    def test_repeated_phrase_ambiguous_fail(self):
        q="gói bị lỗi; gói bị lỗi"
        a={"claims":[{"id":"c1","excerpt":"gói bị lỗi","intent":"policy_question","needs_case_data":False}],
           "unresolved":[]}
        with self.assertRaisesRegex(SpanRejected,"ambiguous"):self.resolve(a,q)
    def test_non_verbatim_source_fails(self):
        p=copy.deepcopy(self.response);p['claims'][0]['excerpt']="Gói đã được kích hoạt"
        with self.assertRaisesRegex(SpanRejected,"nonverbatim"):self.resolve(p)
    def test_dropped_intent_fails(self):
        p=copy.deepcopy(self.response);p['claims']=p['claims'][:1]
        with self.assertRaisesRegex(SpanRejected,"dropped"):self.resolve(p)
    def test_overlapping_span_fails(self):
        q="Lỗi hóa đơn; chờ xử lý."
        p={"claims":[
          {"id":"c1","excerpt":"Lỗi hóa đơn; chờ","intent":"policy_question","needs_case_data":False},
          {"id":"c2","excerpt":"chờ xử lý.","intent":"requested_action","needs_case_data":False}],
          "unresolved":[]}
        with self.assertRaisesRegex(SpanRejected,"overlap"):self.resolve(p,q)
    def test_unresolved_span_preserves_unclear_input(self):
        p=copy.deepcopy(self.response)
        p['claims']=p['claims'][:1]
        p['unresolved']=[{"excerpt":self.question.split("; ")[1],"reason":"ambiguous"}]
        x=self.resolve(p)
        self.assertEqual(x['unresolved_count'],1)
        self.assertTrue(x['all_alphanumeric_source_covered'])
    def test_invalid_unresolved_reason_fails(self):
        p=copy.deepcopy(self.response)
        p['unresolved']=[{"excerpt":self.question.split("; ")[1],"reason":"approve_refund"}]
        with self.assertRaises(SpanRejected):self.resolve(p)
    def test_unexpected_business_action_field_fails(self):
        p=copy.deepcopy(self.response);p['business_write']="refund"
        with self.assertRaises(SpanRejected):self.resolve(p)
    def test_email_like_input_never_sent_forward(self):
        q="Please contact alice@example.com for refund!"
        with self.assertRaisesRegex(SpanRejected,"private"):self.resolve(self.response,q)
    def test_invalid_boolean_type_rejected(self):
        p=copy.deepcopy(self.response);p['claims'][0]['needs_case_data']="false"
        with self.assertRaises(SpanRejected):self.resolve(p)
    def test_duplicate_claim_id_rejected(self):
        p=copy.deepcopy(self.response);p['claims'][1]['id']="c1"
        with self.assertRaises(SpanRejected):self.resolve(p)
    def test_extraneous_model_generated_offsets_rejected(self):
        p=copy.deepcopy(self.response);p['claims'][0]['source_start']=20
        with self.assertRaises(SpanRejected):self.resolve(p)
    def test_tenant_locale_mismatch_rejected(self):
        with self.assertRaises(SpanRejected):
            recover(self.question,self.response,tenant="other-tenant",locale="vi")
    def test_raw_text_or_markdown_not_accepted(self):
        with self.assertRaises(SpanRejected):self.resolve("claims: []")
    def test_nonstring_query_rejected(self):
        with self.assertRaises(SpanRejected):self.resolve(self.response,123)
if __name__=="__main__":
    unittest.main(verbosity=2)
