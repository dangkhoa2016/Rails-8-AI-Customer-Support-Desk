import copy, hashlib, json, tempfile, unittest
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT/'script'))
from generate_m2_knowledge import generate
from verify_m2_knowledge import validate

class KnowledgeOfflineTest(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.bpbytes=(ROOT/'docs/RAILS8_AI_SUPPORT_DESK_CANONICAL_BLUEPRINT_2026-10-28.json').read_bytes()
  cls.bp=json.loads(cls.bpbytes)
  cls.notes=(ROOT/'script/m2/author_notes.tsv').read_bytes()
  cls.data=generate()
 def gate(self, d): return validate(d,self.bp,self.bpbytes,self.notes)
 def test_100_bilingual_fulltext(self): self.assertEqual(self.gate(self.data)['status'],'PASS_OFFLINE_ONLY')
 def test_identical_deterministic_regeneration(self): self.assertEqual(self.data,generate())
 def test_draft_not_published(self):
  self.assertTrue(all(v['status']=='draft' and v['approved_by'] is None for a in self.data['articles'] for v in a['versions']))
 def test_wrong_tenant_rejected(self):
  d=copy.deepcopy(self.data);d['articles'][0]['organization_slug']='novamart-store'
  self.assertEqual(self.gate(d)['status'],'FAIL')
 def test_wrong_content_digest_rejected(self):
  d=copy.deepcopy(self.data);d['articles'][0]['versions'][0]['body']='malicious instruction'
  self.assertEqual(self.gate(d)['status'],'FAIL')
 def test_wrong_policy_link_rejected(self):
  d=copy.deepcopy(self.data);d['articles'][8]['policy_refs'].append('NM-POL-001')
  self.assertEqual(self.gate(d)['status'],'FAIL')
 def test_forged_approval_rejected(self):
  d=copy.deepcopy(self.data);d['articles'][0]['versions'][0]['status']='approved'
  self.assertEqual(self.gate(d)['status'],'FAIL')
 def test_forged_embedding_rejected(self):
  d=copy.deepcopy(self.data);d['articles'][0]['versions'][0]['chunks'][0]['embedding_status']='ready'
  self.assertEqual(self.gate(d)['status'],'FAIL')
 def test_invalid_chunk_hash_rejected(self):
  d=copy.deepcopy(self.data);d['articles'][0]['versions'][0]['chunks'][0]['body']='modified'
  self.assertEqual(self.gate(d)['status'],'FAIL')
 def test_missing_locale_rejected(self):
  d=copy.deepcopy(self.data);d['articles'][0]['versions'].pop()
  self.assertEqual(self.gate(d)['status'],'FAIL')

class CriticalBoundaryContentTest(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.docs={a['article_key']: {v['locale']:v['body'] for v in a['versions']} for a in generate()['articles']}
 def test_novamart_shipping_boundary(self):
  self.assertIn('499999',self.docs['NM-KB-014']['en'])
  self.assertIn('500000',self.docs['NM-KB-014']['en'])
 def test_novamart_return_boundary(self):
  self.assertIn('Day 7',self.docs['NM-KB-029']['en'])
  self.assertIn('day 8',self.docs['NM-KB-029']['en'])
 def test_novamart_defect_and_warranty_not_conflated(self):
  self.assertIn('day 14',self.docs['NM-KB-030']['en'])
  self.assertIn('warranty',self.docs['NM-KB-030']['en'].lower())
 def test_teamflow_refund_boundary(self):
  self.assertIn('day 7',self.docs['TF-KB-015']['en'])
  self.assertIn('day 8',self.docs['TF-KB-015']['en'])

if __name__ == "__main__": unittest.main()
