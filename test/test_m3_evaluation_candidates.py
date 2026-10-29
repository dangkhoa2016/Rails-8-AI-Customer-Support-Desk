#!/usr/bin/env python3
"""Independent offline checks for non-gold evaluation candidates."""
import collections
import hashlib
import json
import pathlib
import unittest

ROOT=pathlib.Path(__file__).resolve().parents[1]
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()

class M3EvaluationCandidatesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data=json.loads((ROOT/'data/m3_support_evaluation_candidates_120.json').read_text())
        cls.manifest=json.loads((ROOT/'data/m3_support_evaluation_candidates_120.manifest.json').read_text())
        cls.source=json.loads((ROOT/'evidence-m2-claim64-provisional-audit-20261029/approved-kb-v2-readonly-snapshot.json').read_text())

    def test_source_unchanged(self):
        self.assertEqual(self.data['source_snapshot_sha256'],digest(ROOT/'evidence-m2-claim64-provisional-audit-20261029/approved-kb-v2-readonly-snapshot.json'))
        self.assertEqual(self.data['source_m3_sha256'],digest(ROOT/'data/m3_synthetic_tickets.json'))

    def test_manifest_sha(self):
        self.assertEqual(self.manifest['dataset_sha256'],digest(ROOT/'data/m3_support_evaluation_candidates_120.json'))

    def test_counts_and_uniq(self):
        cases=self.data['cases'];self.assertEqual(len(cases),120)
        self.assertEqual(len({r['question'] for r in cases}),120)
        self.assertEqual(len({r['case_id'] for r in cases}),120)

    def test_source_links(self):
        known={(r['tenant'],r['locale'],r['article_key']):r['body_sha256'] for r in self.source['articles']}
        for r in self.data['cases']:
            self.assertEqual(known[r['tenant'],r['locale'],r['source_article_key']],r['source_approved_body_sha256'])
            self.assertEqual(r['source_approved_version'],2)

    def test_all_non_gold(self):
        self.assertFalse(self.data['semantic_gold'])
        self.assertEqual(self.data['answerability_gate'],'BLOCKED')
        self.assertTrue(all(c['gold_answer'] is None and c['independent_human_review']=='NOT_PERFORMED' for c in self.data['cases']))

    def test_strata(self):
        counts=collections.Counter(r['evaluation_intent_hint'] for r in self.data['cases'])
        self.assertEqual(counts,{'policy_retrieval':48,'needs_case_evidence':36,'unsafe_or_unsupported_claim':36})
        loc=collections.Counter((r['tenant'],r['locale']) for r in self.data['cases'])
        self.assertEqual(loc, {('teamflow-cloud','vi'):20,('teamflow-cloud','en'):20,('novamart-store','vi'):40,('novamart-store','en'):40})

if __name__=='__main__':unittest.main(verbosity=2)
