#!/usr/bin/env python3
"""Offline M2 gate: exact 100 article IDs, 2 locales, M0 policy refs, SHA256, status and source.
Intentionally not a Rails/pgvector/Modal benchmark.
"""
import argparse, collections, hashlib, json, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent

def digest(s): return hashlib.sha256(s.encode('utf-8')).hexdigest()

def validate(payload, blueprint, blueprint_bytes, notes_bytes):
    errors = []
    def check(cond, msg):
        if not cond: errors.append(msg)
    arts = payload.get('articles', [])
    catalogs = {a['id']: (o, a) for o in blueprint['organizations'] for a in o['knowledge_article_catalog']}
    actual = [a.get('article_key') for a in arts]
    check(len(arts) == 100, 'article_count')
    check(len(set(actual)) == len(actual), 'article_duplicates')
    check(set(actual) == set(catalogs), 'catalog_exact_match')
    check(payload.get('source_blueprint_sha256') == hashlib.sha256(blueprint_bytes).hexdigest(), 'source_blueprint_sha256')
    check(payload.get('author_notes_sha256') == hashlib.sha256(notes_bytes).hexdigest(), 'author_notes_sha256')
    check(payload.get('policy_version') == blueprint.get('policy_version'), 'policy_version')
    check(payload.get('publication_status') == 'PENDING_HUMAN_EDITORIAL_APPROVAL', 'publication_unapproved')
    check(payload.get('modal_embedding_status') == 'NOT_RUN', 'embedding_should_be_not_run')
    counts = collections.Counter()
    seen_bodies = set()
    for a in arts:
        key = a.get('article_key')
        if key not in catalogs: continue
        org, cat = catalogs[key]
        check(a.get('organization_slug') == org['slug'], key+':tenant')
        check(a.get('category') == cat['category'], key+':category')
        exp_policy = {k for k, v in blueprint['policy_knowledge_links'].items() if key in v}
        check(set(a.get('policy_refs', [])) == exp_policy, key+':policy_links')
        check(a.get('audience') in {'public', 'agent'}, key+':audience')
        vers = a.get('versions', [])
        check(len(vers) == 2 and set(v.get('locale') for v in vers) == {'vi', 'en'}, key+':locales')
        counts[org['slug']+':articles'] += 1
        for v in vers:
            loc = v.get('locale')
            counts[org['slug']+':'+str(loc)] += 1
            body = v.get('body', '')
            check(v.get('version') == 1, key+':version_number')
            check(v.get('title') == cat.get('title_'+str(loc)), key+':title')
            check(v.get('status') == 'draft' and v.get('approved_by') is None and v.get('approved_at') is None, key+':draft_status')
            check(v.get('effective_from') == '2026-10-28' and v.get('effective_to') is None, key+':dates')
            check(digest(body) == v.get('sha256'), key+':content_hash')
            check(len(body) >= 700, key+':body_min_length')
            check(body not in seen_bodies, key+':duplicate_body')
            seen_bodies.add(body)
            chunks = v.get('chunks', [])
            check(len(chunks) >= 6, key+':chunk_count')
            check(''.join(c.get('body', '') for c in chunks) == body, key+':reassembly')
            check(all(c.get('chunk_index') == i and digest(c.get('body', '')) == c.get('sha256') for i, c in enumerate(chunks)), key+':chunk_hash')
            check(all(c.get('embedding_status') == 'not_generated' and c.get('vector') is None for c in chunks), key+':no_inference')
            counts['versions'] += 1
            counts['chunks'] += len(chunks)
    check(counts['teamflow-cloud:articles'] == 50 and counts['novamart-store:articles'] == 50, 'tenant_quotas')
    check(counts['versions'] == 200 and counts['chunks'] == 1400, 'version_chunk_quotas')
    return {'status': 'PASS_OFFLINE_ONLY' if not errors else 'FAIL', 'errors': errors, 'counts': dict(counts),
            'validation_scope': 'JSON structure + canonical policy links + checksums; no PostgreSQL/Modal inference',
            'editorial_approval': 'NOT_PERFORMED', 'postgresql_runtime': 'NOT_RUN', 'modal_embeddings': 'NOT_RUN'}

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--dataset',default=str(ROOT/'data/m2/knowledge_drafts.json'))
    ap.add_argument('--report',default=str(ROOT/'evidence/m2/knowledge-offline-validation.json'))
    args=ap.parse_args(); bp=ROOT/'docs/RAILS8_AI_SUPPORT_DESK_CANONICAL_BLUEPRINT_2026-10-28.json'
    bs=bp.read_bytes();ns=(ROOT/'script/m2/author_notes.tsv').read_bytes()
    report=validate(json.loads(Path(args.dataset).read_text(encoding='utf8')),json.loads(bs),bs,ns)
    Path(args.report).parent.mkdir(parents=True,exist_ok=True)
    Path(args.report).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print(json.dumps(report,ensure_ascii=False,indent=2))
    return 0 if report['status']=='PASS_OFFLINE_ONLY' else 1
if __name__=='__main__':sys.exit(main())
