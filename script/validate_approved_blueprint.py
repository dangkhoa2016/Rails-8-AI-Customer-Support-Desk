#!/usr/bin/env python3
"""Offline M0 consistency checks, not Rails/DB/AI tests."""
import json
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1] / "docs"
source = json.loads((root/'source_snapshot'/'RAILS8_AI_SUPPORT_DESK_CANONICAL_BLUEPRINT_2026-10-28.json').read_text())
approved = json.loads((root/'RAILS8_AI_SUPPORT_DESK_CANONICAL_BLUEPRINT_2026-10-28.json').read_text())
assert approved['policy_approval']['status'] == 'approved_for_synthetic_demo'
assert approved['policy_version'] == approved['global']['policy_version'] == '1.0.0'
assert approved['status'] == 'design_blueprint_not_generated_dataset'
assert approved['reference_cases'] == source['reference_cases']
assert approved['reference_fixture_blueprints'] == source['reference_fixture_blueprints']
assert approved['policy_knowledge_links'] == source['policy_knowledge_links']
assert len(approved['organizations']) == 2
assert len(approved['implementation_clarifications']) == 8
assert len(approved['reference_cases']) == 20
assert len(approved['reference_fixture_blueprints']) == 2
assert approved['global']['dataset_target'] == source['global']['dataset_target']
assert approved['global']['evaluation_split_per_org'] == source['global']['evaluation_split_per_org']
assert approved['global']['evaluation_strata_per_org'] == source['global']['evaluation_strata_per_org']
assert approved['global']['ticket_priorities'] == source['global']['ticket_priorities']
for org in approved['organizations']:
    orig = next(o for o in source['organizations'] if o['slug'] == org['slug'])
    assert orig == org, f"original business policy changed: {org['slug']}"
    assert len(org['rules']) == 10
    assert len(org['knowledge_article_catalog']) == 50
    assert org['targets']['tickets'] == 120
    assert org['targets']['evaluation_cases'] == 60
    assert org['targets']['ticket_vi'] == 60 and org['targets']['ticket_en'] == 60
    assert set(org['first_response_sla_business_hours']) == {'P1','P2','P3','P4'}
    assert sum(org['ticket_categories'].values()) == 120
    assert sum(org['knowledge_categories'].values()) == 50
policy_ids={r['id'] for o in approved['organizations'] for r in o['rules']}
assert len(policy_ids)==20
for c in approved['implementation_clarifications']:
    assert set(c['policy_refs']).issubset(policy_ids)
    assert c['en'].strip() and c['vi'].strip()
assert approved['global']['default_ai_mode'] == 'human_approval_required'
assert 'send_message' in approved['global']['no_ai_mutations']
# Publication-safe validation relies on the canonical, content-addressed JSON
# fixtures, not internal editorial approval/handoff documents.
assert approved['policy_version'] == approved['global']['policy_version']
assert source['status'] == 'design_blueprint_not_generated_dataset'
assert approved['policy_approval']['status'] == 'approved_for_synthetic_demo'
assert all(rule['id'] for org in approved['organizations'] for rule in org['rules'])
print('PASS: M0 approved policy metadata, 20 policy IDs, 100 KB catalog titles, 20 reference cases, 2 planned fixtures')
print('PASS: original business policies/prices/quotas were preserved; bilingual clarifications; AI human approval remains default')
print('Status: OFFLINE STATIC VALIDATION ONLY; Rails/PostgreSQL/Modal NOT_RUN')
