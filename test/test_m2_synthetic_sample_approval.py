#!/usr/bin/env python3
"""Owner-approved SYNTHETIC-SAMPLE-ONLY acceptance contract.
Never claims actual human reviewer judgement, real-world truth or AI answer safety.
"""
from collections import Counter
from pathlib import Path
import hashlib,json,unittest

ROOT=Path(__file__).resolve().parents[1]
QUEUE=ROOT/"evidence-m2-claim32x2-20261029/claim-level-blind-human-validation.json"
KB=ROOT/"evidence-m2-claim64-provisional-audit-20261029/approved-kb-v2-readonly-snapshot.json"
SAMPLE=ROOT/"review/m2_claim64_synthetic_demo_approval_20261029.json"
PAGES=ROOT/"evidence-m2-claim64-independent-review-v2-20261029"

class SampleContentApprovalContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.m=json.loads(SAMPLE.read_text())
        cls.q=json.loads(QUEUE.read_text())
        cls.k=json.loads(KB.read_text())
    def test_exact_64_immutable_claim_ids_and_text(self):
        original={r["claim_id"]:r for r in self.q["tasks"]}
        demo={r["claim_id"]:r for r in self.m["claims"]}
        self.assertEqual(len(original),64);self.assertEqual(set(original),set(demo))
        for ident,record in demo.items():
            self.assertEqual(record["parent_question"],original[ident]["parent_question"])
            self.assertEqual(record["atomic_claim"],original[ident]["atomic_claim"])
            self.assertEqual((record["tenant"],record["locale"]),(original[ident]["tenant"],original[ident]["locale"]))
    def test_all_approved_only_for_synthetic_demo_content(self):
        self.assertEqual(self.m["claims_accepted_for_demo"],64)
        self.assertTrue(all(r["sample_content_status"]=="APPROVED_FOR_SYNTHETIC_DEMO" for r in self.m["claims"]))
        self.assertEqual(self.m["dataset_sample_status"],"APPROVED_FOR_SYNTHETIC_DEMO")
        self.assertEqual(self.m["scope"],"CONTENT_FOR_LOCAL_DEMO_PRESENTATION_AND_RELEVANCE_ONLY_RESEARCH")
    def test_all_original_decisions_remain_pending_not_fake_signed(self):
        self.assertTrue(all(r["human_decision_status"]=="PENDING_MANUAL_VERIFICATION" for r in self.q["tasks"]))
        self.assertTrue(all(r["human_policy_supported"] is None for r in self.q["tasks"]))
        self.assertIs(self.m["human_reviewer_labels_or_signatures_created"],False)
    def test_frozen_provenance(self):
        self.assertEqual(self.m["frozen_claim_queue_sha256"],hashlib.sha256(QUEUE.read_bytes()).hexdigest())
        self.assertEqual(self.m["frozen_approved_kb_snapshot_sha256"],hashlib.sha256(KB.read_bytes()).hexdigest())
    def test_kb_exact_approved_12_only_and_does_not_approve_drafts(self):
        self.assertEqual(self.m["approved_kb_source_count"],12)
        docs={(x["tenant"],x["locale"],x["article_key"]):x for x in self.k["articles"]}
        self.assertEqual(len(self.m["kb_articles"]),len(docs))
        for record in self.m["kb_articles"]:
            original=docs[(record["tenant"],record["locale"],record["article_key"])]
            self.assertEqual(record["body_sha256"],original["body_sha256"])
            self.assertEqual(original["article_version_number"],record["approved_version"])
        self.assertEqual(self.m["db_article_version_states"],"UNCHANGED")
    def test_human_review_waived_only_for_sample_display(self):
        self.assertEqual(self.m["human_review_requirement_for_sample_display"],"WAIVED_BY_OWNER_ONLY_FOR_SYNTHETIC_DEMO")
        self.assertEqual(self.m["manual_review_workbook_status"],"OPTIONAL_FUTURE_VALIDATION_NOT_A_DEMO_PREREQUISITE")
    def test_not_assert_real_world_policy_truth(self):
        self.assertFalse(self.m["atomic_policy_truth_assumed"])
        self.assertFalse(self.m["all_claims_assumed_affirmative"])
        self.assertTrue(all(r["real_world_truth"]=="NOT_VERIFIED" for r in self.m["claims"]))
        self.assertTrue(all(r["policy_answerability"]=="UNKNOWN_NOT_APPROVED" for r in self.m["claims"]))
    def test_safety_gates_never_relaxed(self):
        self.assertEqual(self.m["scope_gate"],"BLOCKED_PREVIOUS_SEALED80_FALSE_POSITIVES")
        self.assertEqual(self.m["automated_customer_answer"],"NOT_AUTHORIZED")
        self.assertEqual(self.m["ai_business_writes"],"PROHIBITED")
        self.assertEqual(self.m["production_readiness"],"NOT_CLAIMED")
    def test_html_both_locales_include_all_64_and_12(self):
        for lang in ("vi","en"):
            page=(PAGES/f"sample-approval.{lang}.html").read_text()
            self.assertEqual(page.count('class="card sample-claim"'),64)
            self.assertEqual(page.count('<article><strong>'),12)
            self.assertIn(self.m["frozen_claim_queue_sha256"],page)
            self.assertIn(self.m["frozen_approved_kb_snapshot_sha256"],page)
    def test_html_no_network_or_active_business_mutation(self):
        for lang in ("vi","en"):
            page=(PAGES/f"sample-approval.{lang}.html").read_text()
            for text in ("fetch(","localStorage","XMLHttpRequest","APPROVED_FOR_BUSINESS_WRITE"):
                self.assertNotIn(text,page)
    def test_exact_four_strata(self):
        groups=Counter((x["tenant"],x["locale"]) for x in self.m["claims"])
        self.assertEqual(set(groups.values()),{16})
        self.assertEqual(len(groups),4)

if __name__=="__main__":unittest.main(verbosity=2)
