#!/usr/bin/env python3
"""Synthetic review fixtures only. Never use these as human decisions."""
from pathlib import Path
import json,sys,tempfile,unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"script"))
from compare_m2_dual_external_reviews import compare
from validate_m2_external_review_export import QUEUE,SNAP,sha
class DualReviewUnit(unittest.TestCase):
 def setUp(self):
    self.t=tempfile.TemporaryDirectory();self.a=Path(self.t.name)/"fake_a.json";self.b=Path(self.t.name)/"fake_b.json"
    q=json.loads(QUEUE.read_text());s=json.loads(SNAP.read_text())
    by={(d["tenant"],d["locale"]):[] for d in s["articles"]}
    for d in s["articles"]:by[(d["tenant"],d["locale"])].append(d)
    ds=[]
    for i,t in enumerate(q["tasks"]):
      label=("affirmative_policy","explicit_negative_policy","not_documented")[i%3]
      doc=by[(t["tenant"],t["locale"])][0] if label!="not_documented" else None
      ds.append({"claim_id":t["claim_id"],"tenant":t["tenant"],"locale":t["locale"],
        "reviewer_decision":label,"evidence_article":doc["article_key"] if doc else None,
        "evidence_quote_or_section":doc["body"][:100] if doc else "",
        "reviewer_notes":"UNITTEST FIXTURE ONLY - NOT AN ACTUAL REVIEW OR POLICY VERDICT."})
    self.x={"source_manifest_sha256":q["source_manifest_sha256"],
       "candidate_evidence_sha256":q["model_evidence_sha256"],
       "approved_snapshot_sha256":sha(SNAP),
       "reviewer_id":"SYNTHETIC_UNIT_TEST_A",
       "self_attested_independent_review":True,
       "review_status":"COMPLETE_SELF_ATTESTED_UNVERIFIED",
       "completion":64,"total":64,"decisions":ds}
    self.y=json.loads(json.dumps(self.x));self.y["reviewer_id"]="SYNTHETIC_UNIT_TEST_B"
 def tearDown(self):self.t.cleanup()
 def evaluate(self):
    self.a.write_text(json.dumps(self.x));self.b.write_text(json.dumps(self.y))
    return compare(self.a,self.b)
 def test_identical_fake_labels_never_release(self):
    r=self.evaluate();self.assertEqual(r["agreement_count"],64)
    self.assertFalse(r["automatic_release"]);self.assertFalse(r["verified_identity"])
    self.assertFalse(r["verified_independence"]);self.assertEqual(r["claim_level_release"],"BLOCKED")
 def test_detect_label_disagreement(self):
    d=self.y["decisions"][0];d.update({"reviewer_decision":"not_documented","evidence_article":None,"evidence_quote_or_section":""})
    r=self.evaluate();self.assertEqual(r["agreement_count"],63);self.assertEqual(r["arbitration_issue_count"],1)
 def test_detect_citation_disagreement(self):
    d=self.y["decisions"][0]
    docs=json.loads(SNAP.read_text())["articles"]
    alt=next(x for x in docs if x["tenant"]==d["tenant"] and x["locale"]==d["locale"] and x["article_key"]!=d["evidence_article"])
    d["evidence_article"]=alt["article_key"];d["evidence_quote_or_section"]=alt["body"][:100]
    r=self.evaluate();self.assertEqual(r["agreement_count"],64);self.assertEqual(r["arbitration_issue_count"],1)
 def test_same_reviewer_id_rejected(self):
    self.y["reviewer_id"]=self.x["reviewer_id"]
    with self.assertRaises(AssertionError):self.evaluate()
 def test_missing_self_attestation_rejected(self):
    self.y["self_attested_independent_review"]=False
    with self.assertRaises(AssertionError):self.evaluate()
 def test_pending_rejected(self):
    self.y["decisions"][0]["reviewer_decision"]=None
    with self.assertRaises(AssertionError):self.evaluate()
 def test_cross_tenant_citation_rejected(self):
    self.y["decisions"][0]["evidence_article"]="NM-KB-014"
    with self.assertRaises(AssertionError):self.evaluate()
 def test_wrong_kb_snapshot_rejected(self):
    self.y["approved_snapshot_sha256"]="0"*64
    with self.assertRaises(AssertionError):self.evaluate()
if __name__=="__main__":unittest.main(verbosity=2)
