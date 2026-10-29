#!/usr/bin/env python3
import hashlib,copy,sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"script"))
from m2_partition_aware_units import source_units,validate_assignments
from m2_deterministic_exact_spans import SpanRejected
class PartitionAwareContractTests(unittest.TestCase):
    def setUp(self):
        self.q="Hóa đơn đã paid; cần kiểm tra activation event? Có thể tự mở quyền Pro không?"
        self.p=source_units(self.q,tenant="teamflow-cloud",locale="vi")
        self.a={"schema":"rails8.m2.partition_labels.v1",
          "question_sha256":self.p["question_sha256"],
          "assignments":[{"unit_id":u["id"],"role":"policy_question",
                           "needs_case_data":False,"reason":None} for u in self.p["units"]]}
    def test_lossless_source_bytes_and_spans(self):
        self.assertEqual(len(self.p["units"]),3)
        self.assertEqual("".join(u["source_excerpt"] for u in self.p["units"]),self.q)
        for u in self.p["units"]:
            self.assertEqual(self.q[u["source_start"]:u["source_end"]],u["source_excerpt"])
    def test_valid_classification_never_authorizes_writes(self):
        result=validate_assignments(self.p,self.a)
        self.assertTrue(result["all_units_exclusively_classified"])
        self.assertFalse(result["semantic_fidelity_verified"])
        self.assertTrue(result["human_review_required"])
        self.assertFalse(result["business_actions_authorized"])
    def test_missing_assignment(self):
        self.a["assignments"].pop()
        with self.assertRaises(SpanRejected):validate_assignments(self.p,self.a)
    def test_duplicate_assignment(self):
        self.a["assignments"][1]["unit_id"]="u1"
        with self.assertRaises(SpanRejected):validate_assignments(self.p,self.a)
    def test_reordered_unit(self):
        self.a["assignments"].reverse()
        with self.assertRaises(SpanRejected):validate_assignments(self.p,self.a)
    def test_stale_question_sha(self):
        self.a["question_sha256"]="0"*64
        with self.assertRaises(SpanRejected):validate_assignments(self.p,self.a)
    def test_extra_business_command(self):
        self.a["assignments"][0]["approve_refund"]=True
        with self.assertRaises(SpanRejected):validate_assignments(self.p,self.a)
    def test_model_generated_excerpts_not_accepted(self):
        self.a["assignments"][0]["excerpt"]="edited"
        with self.assertRaises(SpanRejected):validate_assignments(self.p,self.a)
    def test_unresolved_must_have_reason(self):
        self.a["assignments"][1]["role"]="unresolved"
        with self.assertRaises(SpanRejected):validate_assignments(self.p,self.a)
        self.a["assignments"][1]["reason"]="untrusted_text"
        self.assertTrue(validate_assignments(self.p,self.a)["source_integrity_verified"])
    def test_non_unresolved_must_not_have_reason(self):
        self.a["assignments"][0]["reason"]="untrusted_text"
        with self.assertRaises(SpanRejected):validate_assignments(self.p,self.a)
    def test_json_boolean_strict(self):
        self.a["assignments"][0]["needs_case_data"]="false"
        with self.assertRaises(SpanRejected):validate_assignments(self.p,self.a)
    def test_conservative_unseparated_two_requests_abstains(self):
        q="Có thể trả hàng trong hạn và tự phê duyệt hoàn tiền không?"
        with self.assertRaisesRegex(SpanRejected,"partition_not_reliable"):
            source_units(q,tenant="novamart-store",locale="vi")
    def test_unicode_split_comma_vietnamese(self):
        p=source_units("Tôi đã thanh toán, và có thể kiểm tra activation event không?",tenant="teamflow-cloud",locale="vi")
        self.assertEqual(p["unit_count"],2)
    def test_english_comma_and_boundary(self):
        p=source_units("The invoice is paid, and can staff guarantee an immediate upgrade?",tenant="teamflow-cloud",locale="en")
        self.assertEqual(p["unit_count"],2)
    def test_bad_tenant(self):
        with self.assertRaises(SpanRejected):source_units(self.q,tenant="another",locale="vi")
    def test_email_privacy_rejected(self):
        with self.assertRaises(SpanRejected):source_units("alice@example.com; please issue refund?",tenant="teamflow-cloud",locale="en")
    def test_four_unit_limit(self):
        q="First policy question? Second policy question? Third policy question? Fourth policy question? Fifth policy question?"
        with self.assertRaisesRegex(SpanRejected,"partition_not_reliable"):
            source_units(q,tenant="teamflow-cloud",locale="en")
    def test_source_only_ignores_role_semantics(self):
        self.a["assignments"][0]["role"]="requested_action"
        self.assertFalse(validate_assignments(self.p,self.a)["semantic_fidelity_verified"])
if __name__=="__main__":unittest.main(verbosity=2)
