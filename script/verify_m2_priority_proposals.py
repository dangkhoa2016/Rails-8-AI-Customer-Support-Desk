#!/usr/bin/env python3
"""Offline integrity + policy-boundary checks for 12 human-reviewable v2 drafts."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
P = ROOT / 'review/m2_priority_editorial_proposals_20261029.json'
S = ROOT / 'data/m2/knowledge_drafts.json'
C = ROOT / 'data/policy/canonical_blueprint.json'
hash_bytes = lambda b: hashlib.sha256(b).hexdigest()
obj = json.loads(P.read_text(encoding='utf-8'))
original = json.loads(S.read_text(encoding='utf-8'))
canonical = json.loads(C.read_text(encoding='utf-8'))
errors = []
check = lambda cond, description: errors.append(description) if not cond else None
check(obj['source_m2_sha256'] == hash_bytes(S.read_bytes()), 'original source changed')
check(obj['canonical_sha256'] == hash_bytes(C.read_bytes()), 'approved canonical changed')
check(obj['policy_version'] == canonical['policy_version'], 'policy version mismatch')
articles = {a['article_key']: a for a in original['articles']}
policies = {r['id']: r for org in canonical['organizations'] for r in org['rules']}
clarifications = {r['id']: r for r in canonical['implementation_clarifications']}
revs = obj['revisions']
check(len(revs) == 12, 'expected exactly twelve proposed versions')
check(len({(r['article_key'], r['locale']) for r in revs}) == 12, 'duplicate article/locale')
for rev in revs:
  key,lang = rev['article_key'],rev['locale']
  source = articles.get(key)
  check(source is not None and lang in ('vi','en'), f'invalid source {key}:{lang}')
  if not source: continue
  old = next(v for v in source['versions'] if v['locale'] == lang)
  check(rev['based_on_v1_sha256'] == old['sha256'], f'v1 basis mismatch {key}:{lang}')
  check(rev['policy_refs'] == source['policy_refs'], f'changed policy refs {key}:{lang}')
  check(rev['version'] == 2 and rev['status'] == 'draft' and rev['approved_by'] is None and rev['approved_at'] is None,
    f'unexpected approval or version {key}:{lang}')
  check(hash_bytes(rev['body'].encode('utf-8')) == rev['sha256'], f'bad digest {key}:{lang}')
  check(len(rev['chunks']) == 7 and ''.join(c['body'] for c in rev['chunks']) == rev['body'], f'chunk reconstruction {key}:{lang}')
  for c in rev['chunks']:
    check(hash_bytes(c['body'].encode('utf-8')) == c['sha256'], f'chunk digest {key}:{lang}:{c["chunk_index"]}')
  for pid in rev['policy_refs'] + rev['clarification_refs']:
    record = policies.get(pid) or clarifications.get(pid)
    check(record is not None and f'**{pid}**' in rev['body'] and record[lang] in rev['body'], f'canonical policy text mismatch {key}:{lang}:{pid}')
  # Case-specific edge facts. These guards are not a substitute for human review.
  required = {
    'TF-KB-012': {'vi':['activation','effective_plan','paid'], 'en':['activation','effective_plan','paid']},
    'TF-KB-015': {'vi':['ngày 0','ngày 7','ngày 8'], 'en':['day 0','day 8','human']},
    'NM-KB-014': {'vi':['499.999','500.000','30.000'], 'en':['499,999','500,000','30,000']},
    'NM-KB-020': {'vi':['2 ngày làm việc','2–5','không'], 'en':['2 business days','2–5','not']},
    'NM-KB-029': {'vi':['ngày 0','Ngày 0–7','ngày 8'], 'en':['day 0','Days 0–7','day 8']},
    'NM-KB-030': {'vi':['ngày 14','Ngày 15','warranty_months'], 'en':['day 14','Day 15','warranty_months']},
  }
  for needle in required[key][lang]:
    check(needle.lower() in rev['body'].lower(), f'missing boundary evidence {key}:{lang}:{needle}')
result = {'status': 'PASS_SOURCE_ONLY' if not errors else 'FAIL', 'proposed_article_ids': 6,
          'proposed_language_versions': len(revs), 'v2_chunks': sum(len(v['chunks']) for v in revs),
          'canonical_source_sha256': hash_bytes(C.read_bytes()), 'm2_original_sha256': hash_bytes(S.read_bytes()),
          'proposal_sha256': hash_bytes(P.read_bytes()), 'human_approved': 0, 'errors': errors}
print(json.dumps(result, ensure_ascii=False, indent=2))
raise SystemExit(0 if not errors else 1)
