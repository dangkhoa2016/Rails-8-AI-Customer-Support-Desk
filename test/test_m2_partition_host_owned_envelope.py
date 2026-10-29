#!/usr/bin/env python3
import sys,copy,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"script"))
from m2_partition_aware_units import source_units
from m2_partition_host_owned_envelope import classify_from_model_only
from m2_deterministic_exact_spans import SpanRejected

class HostOwnedEnvelopeTests(unittest.TestCase):
    def setUp(self):
        self.p=source_units("Can the refund request be reviewed? Is approval automatic?",
            tenant="teamflow-cloud",locale="en")
        self.a={"assignments":[{"unit_id":u["id"],"role":"policy_question",
                                 "needs_case_data":False,"reason":None}
                                for u in self.p["units"]]}
    def run_valid(self):
        return classify_from_model_only(self.p,self.a)
    def test_host_owns_all_source_metadata(self):
        out=self.run_valid()
        self.assertEqual(out["question_sha256"],self.p["question_sha256"])
        self.assertEqual(out["trusted_metadata_origin"],"host_precomputed_source_partition")
        self.assertFalse(out["model_supplied_source_metadata"])
        self.assertFalse(out["business_actions_authorized"])
        self.assertFalse(out["semantic_fidelity_verified"])
    def test_model_schema_injection_rejected(self):
        self.a["schema"]="fake"
        with self.assertRaises(SpanRejected):self.run_valid()
    def test_model_source_sha_injection_rejected(self):
        self.a["question_sha256"]="0"*64
        with self.assertRaises(SpanRejected):self.run_valid()
    def test_refund_write_injection_rejected(self):
        self.a["approve_refund"]=True
        with self.assertRaises(SpanRejected):self.run_valid()
    def test_missing_unit_rejected(self):
        self.a["assignments"].pop()
        with self.assertRaises(SpanRejected):self.run_valid()
    def test_reordered_unit_rejected(self):
        self.a["assignments"].reverse()
        with self.assertRaises(SpanRejected):self.run_valid()
    def test_untrusted_span_can_be_exclusively_unresolved(self):
        self.a["assignments"][0]["role"]="unresolved"
        self.a["assignments"][0]["reason"]="untrusted_text"
        out=self.run_valid()
        self.assertEqual(out["source_units"][0]["role"],"unresolved")
    def test_no_auto_customer_answer(self):
        out=self.run_valid()
        self.assertFalse(out["customer_answer_permitted"])
        self.assertTrue(out["human_review_required"])
if __name__=="__main__":unittest.main(verbosity=2)
