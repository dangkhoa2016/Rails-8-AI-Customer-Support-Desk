#!/usr/bin/env python3
"""Independent, read-only M3 synthetic dataset integrity and tenancy validator."""
import collections
import datetime as dt
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
M1_FILE = ROOT / "data/m1_business_records.json"
M3_FILE = ROOT / "data/m3_synthetic_tickets.json"
MANIFEST_FILE = ROOT / "data/m3_synthetic_tickets.manifest.json"
TABLE_REFERENCE_FIELD = {
    "tf_invoices": "invoice_number", "tf_workspaces": "workspace_key",
    "tf_export_jobs": "job_key", "tf_api_request_events": "request_id",
    "tf_subscriptions": "workspace_key", "tf_service_incidents": "incident_key",
    "nm_orders": "order_number", "nm_payments": "payment_key",
    "nm_shipments": "shipment_key", "nm_return_requests": "request_key",
    "nm_warranty_claims": "claim_key",
}
CATEGORIES = {
    "teamflow-cloud": set("billing_subscription permissions_workspace exports_jobs integrations_api incidents_bugs general_howto".split()),
    "novamart-store": set("order_status payment_issues shipping_exceptions returns_refunds product_warranty missing_wrong_damaged".split()),
}
STATES = set("new open pending_customer pending_internal resolved closed".split())
PRIORITIES = set("P1 P2 P3 P4".split())
EXPECTED_STATUSES = {state: 20 for state in STATES}
EXPECTED_LANG = {"vi": 60, "en": 60}

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def verify():
    source = json.loads(M1_FILE.read_text())
    dataset = json.loads(M3_FILE.read_text())
    manifest = json.loads(MANIFEST_FILE.read_text())
    rows = source["records"]
    assert dataset["kind"] == "M3_SYNTHETIC_SUPPORT_TICKETS_V1"
    assert dataset["seed"] == manifest["seed"] == 20261029
    assert dataset["source_m1_sha256"] == manifest["source_m1_sha256"] == sha(M1_FILE)
    assert manifest["dataset_sha256"] == sha(M3_FILE)
    assert dataset["human_approval_required"] is True
    assert dataset["ai_business_writes"] == "PROHIBITED"
    assert manifest["existing_sealed80_scope_gate"] == "BLOCKED"
    assert manifest["not_a_semantic_gold_dataset"] is True
    assert manifest["db_import_execution"] == "NOT_RUN"
    tickets = dataset["tickets"]
    assert len(tickets) == manifest["ticket_count"] == 240
    customers = {(r["organization"], r["external_key"]): r for r in rows["customers"]}
    workspaces = {r["workspace_key"]: r["customer_key"] for r in rows["tf_workspaces"]}
    orders = {r["order_number"]: r["customer_key"] for r in rows["nm_orders"]}
    refs = {}
    for table, field in TABLE_REFERENCE_FIELD.items():
        for record in rows[table]:
            k = (record["organization"], table, record[field])
            assert k not in refs, k
            refs[k] = record
    by_org = collections.Counter()
    by_locale = collections.Counter()
    by_status = collections.Counter()
    by_priority = collections.Counter()
    by_category = collections.Counter()
    by_category_locale = collections.Counter()
    all_numbers = set()
    all_keys = set()
    messages_count = 0
    clock = dt.datetime.fromisoformat(dataset["reference_time"])
    for t in tickets:
        org, key = t["organization"], t["customer_key"]
        assert org in CATEGORIES
        assert t["number"] not in all_numbers
        all_numbers.add(t["number"])
        assert re.fullmatch(r"(TF|NM)-M3-\d{4}", t["number"])
        assert t["category"] in CATEGORIES[org] and t["priority"] in PRIORITIES
        assert t["status"] in STATES and t["synthetic"] is True
        assert t["ai_generated"] is False and t["human_policy_gold"] is None
        customer = customers[(org, key)]
        assert customer["locale"] == t["locale"]
        ref = refs[(org, t["source_table"], t["business_ref"])]
        assert ref["organization"] == org
        if org == "teamflow-cloud" and t["source_table"] != "tf_service_incidents":
            assert workspaces[ref["workspace_key"]] == key
        if org == "novamart-store":
            assert orders[ref["order_number"]] == key
        for name, value in t["source_facts"].items():
            assert name in ref and ref[name] == value
        created = dt.datetime.fromisoformat(t["created_at"])
        updated = dt.datetime.fromisoformat(t["updated_at"])
        assert created.tzinfo and updated.tzinfo and created <= updated < clock
        messages = t["messages"]
        assert len(messages) == (1 if t["status"] == "new" else 2)
        assert messages[0]["actor_type"] == "customer" and messages[0]["visibility"] == "public"
        assert messages[0]["sent_at"] == t["created_at"]
        previous = created
        for i, message in enumerate(messages):
            at = dt.datetime.fromisoformat(message["sent_at"])
            assert created <= at <= updated and previous <= at
            previous = at
            assert message["channel"] == "synthetic_seed"
            assert message["body"].strip() and len(message["body"]) <= 10000
            assert message["idempotency_key"] not in all_keys
            all_keys.add(message["idempotency_key"])
            if i > 0:
                assert message["actor_type"] == "agent" and message["visibility"] == "internal"
            messages_count += 1
        by_org[org] += 1
        by_locale[(org, t["locale"])] += 1
        by_status[(org, t["status"])] += 1
        by_priority[(org, t["priority"], t["locale"])] += 1
        by_category[(org, t["category"])] += 1
        by_category_locale[(org, t["category"], t["locale"])] += 1
    assert messages_count == manifest["message_count"] == 440
    assert by_org == {"teamflow-cloud": 120, "novamart-store": 120}
    for org in CATEGORIES:
        assert {lang: by_locale[org, lang] for lang in EXPECTED_LANG} == EXPECTED_LANG
        assert {state: by_status[org, state] for state in STATES} == EXPECTED_STATUSES
        for priority in PRIORITIES:
            assert by_priority[(org, priority, "vi")] == by_priority[(org, priority, "en")]
        for category in CATEGORIES[org]:
            assert by_category_locale[(org, category, 'vi')] == by_category_locale[(org, category, 'en')]
    assert dict(by_org) == manifest["counts_by_tenant"]
    assert {f"{o}:{l}": n for (o, l), n in by_locale.items()} == manifest["counts_by_tenant_locale"]
    return {"status": "PASS_OFFLINE_M3_INTEGRITY_ONLY", "tickets": len(tickets),
            "messages": messages_count, "linked_references": len({
                (t["organization"], t["source_table"], t["business_ref"]) for t in tickets}),
            "tenant_locale": {f"{o}:{l}": n for (o, l), n in by_locale.items()},
            "by_category": {f"{o}:{c}": n for (o, c), n in by_category.items()},
            "dataset_sha256": sha(M3_FILE), "source_m1_sha256": sha(M1_FILE),
            "rails_db": "NOT_RUN", "semantic_accuracy": "NOT_VERIFIED"}

if __name__ == "__main__":
    print(json.dumps(verify(), indent=2, ensure_ascii=False, sort_keys=True))
