#!/usr/bin/env python3
"""Offline editorial QA/triage: NEVER changes KB status or grants approval."""
import csv
import datetime as dt
import hashlib
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'data/m2/knowledge_drafts.json'
OUT = ROOT / 'review/checkpoint_20261029'
HIGH_RISK = {'billing_subscription','orders_payments','shipping_delivery','returns_refunds','warranty','incidents_troubleshooting'}


def main():
    data = json.loads(SOURCE.read_text(encoding='utf-8'))
    rows = []
    checks = []
    for a in data['articles']:
        versions = a['versions']
        if sorted(v['locale'] for v in versions) != ['en', 'vi']:
            checks.append(f"INVALID_LOCALES:{a['article_key']}")
        for v in versions:
            flags = []
            if not a['policy_refs']:
                flags.append('NO_DIRECT_POLICY_REF_REVIEW')
            if a['category'] in HIGH_RISK:
                flags.append('HIGH_IMPACT_POLICY_FACT_CHECK')
            if len(v['body']) < 1250:
                flags.append('SHORT_CONTENT_UTILITY_REVIEW')
            if len(v['chunks']) != 7:
                flags.append('UNEXPECTED_CHUNK_STRUCTURE')
            if hashlib.sha256(v['body'].encode('utf-8')).hexdigest() != v['sha256']:
                checks.append(f"BODY_HASH_MISMATCH:{a['article_key']}:{v['locale']}")
            if ''.join(c['body'] for c in v['chunks']) != v['body']:
                checks.append(f"CHUNKS_MISMATCH:{a['article_key']}:{v['locale']}")
            if v['status'] != 'draft' or v.get('approved_by') or v.get('approved_at'):
                checks.append(f"UNEXPECTED_PUBLICATION:{a['article_key']}:{v['locale']}")
            if a['policy_refs'] and any(ref not in v['body'] for ref in a['policy_refs']):
                flags.append('POLICY_REF_NOT_IN_ARTICLE_BODY')
            priority = 'HIGH' if 'HIGH_IMPACT_POLICY_FACT_CHECK' in flags else ('MEDIUM' if not a['policy_refs'] else 'NORMAL')
            rows.append({
                'organization': a['organization_slug'], 'article_id': a['article_key'],
                'category': a['category'], 'locale': v['locale'], 'title': v['title'],
                'priority': priority, 'policy_ids': ';'.join(a['policy_refs']),
                'audience': a['audience'], 'body_sha256': v['sha256'],
                'source_status': v['status'], 'automated_review_flags': ';'.join(flags),
                'recommended_action': 'HUMAN_EDITORIAL_REVIEW',
                'human_decision': '', 'reviewer_notes': '', 'reviewer_id': '', 'reviewed_at_utc': ''
            })
    OUT.mkdir(exist_ok=True, parents=True)
    target = OUT / 'M2_EDITORIAL_REVIEW_QUEUE_200.csv'
    with target.open('w', encoding='utf-8-sig', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader(); w.writerows(sorted(rows, key=lambda r: ({'HIGH': 0, 'MEDIUM': 1, 'NORMAL': 2}[r['priority']], r['article_id'], r['locale'])))
    stats = {
        'status': 'OFFLINE_TRIAGE_ONLY_NO_APPROVAL', 'created_utc': dt.datetime.now(dt.timezone.utc).isoformat(),
        'input_sha256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        'articles': len(data['articles']), 'language_versions': len(rows),
        'chunks': sum(len(v['chunks']) for a in data['articles'] for v in a['versions']),
        'priorities': dict(Counter(r['priority'] for r in rows)),
        'flags': dict(Counter(flag for r in rows for flag in r['automated_review_flags'].split(';') if flag)),
        'human_decisions': 0, 'approved_in_source': 0, 'integrity_issues': checks,
        'editorial_claim': 'No language version has been read and approved by a human through this script'
    }
    (OUT / 'M2_EDITORIAL_REVIEW_QUEUE_SUMMARY.json').write_text(json.dumps(stats, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')
    print(json.dumps(stats, indent=2, ensure_ascii=False))
    raise SystemExit(0 if not checks and len(rows) == 200 else 1)


if __name__ == '__main__':
    main()
