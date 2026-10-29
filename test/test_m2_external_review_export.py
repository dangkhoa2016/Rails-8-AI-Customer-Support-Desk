#!/usr/bin/env python3
import json
import tempfile
from pathlib import Path
import sys
import unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'script'))
from validate_m2_external_review_export import check_file,QUEUE,SNAP,sha

class ExternalReviewVerifierTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        q=json.loads(QUEUE.read_text())
        self.bundle={
          'source_manifest_sha256':q['source_manifest_sha256'],
          'candidate_evidence_sha256':q['model_evidence_sha256'],
          'approved_snapshot_sha256':sha(SNAP),
          'reviewer_id':'FAKE_TEST_FIXTURE_NOT_A_REAL_REVIEWER',
          'decisions':[{
            'claim_id':r['claim_id'],'tenant':r['tenant'],'locale':r['locale'],
            'reviewer_decision':None,'evidence_article':None,
            'evidence_quote_or_section':'','reviewer_notes':''
          } for r in q['tasks']]
        }
        self.path=Path(self.tmp.name)/'not_a_real_human_review.json'
    def tearDown(self):self.tmp.cleanup()
    def run_check(self):
        self.path.write_text(json.dumps(self.bundle))
        return check_file(self.path)
    def test_unfinished_review_remains_pending(self):
        x=self.run_check()
        self.assertEqual(len(x['pending']),64)
        self.assertFalse(x['ready_for_second_reviewer_or_signoff'])
        self.assertIn('NOT_VERIFIED',x['status'])
    def test_duplicate_id_rejected(self):
        self.bundle['decisions'][-1]['claim_id']=self.bundle['decisions'][0]['claim_id']
        with self.assertRaises(AssertionError):self.run_check()
    def test_cross_tenant_policy_evidence_rejected(self):
        x=self.bundle['decisions'][0]
        x['reviewer_decision']='affirmative_policy'
        x['evidence_article']='NM-KB-014'
        x['evidence_quote_or_section']='This is not a real policy quote, no source is present.'
        with self.assertRaises(AssertionError):self.run_check()
    def test_bad_corpus_sha_rejected(self):
        self.bundle['approved_snapshot_sha256']='0'*64
        with self.assertRaises(AssertionError):self.run_check()
    def test_unsupported_requires_written_reason(self):
        x=self.bundle['decisions'][0]
        x['reviewer_decision']='not_documented'
        with self.assertRaises(AssertionError):self.run_check()
if __name__=='__main__':unittest.main(verbosity=2)
