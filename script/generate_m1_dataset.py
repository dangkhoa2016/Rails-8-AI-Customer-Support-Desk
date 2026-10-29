#!/usr/bin/env python3
"""Deterministic, policy-grounded M1 business record generation; no LLM or live customer data.

Outputs natural-key records for Rails importer. A scenario is generated from explicit relationships,
not tickets, gold evaluations or KB full text. Python 3.10+, stdlib only.
"""
import argparse
import hashlib
import json
import random
from datetime import datetime, timedelta, timezone
from pathlib import Path

ICT = timezone(timedelta(hours=7))
REF = datetime(2026, 10, 28, tzinfo=ICT)
SEED = 20261028


def iso(dt):
    return dt.isoformat(timespec="seconds")


def stamp(day, hour=9, minute=0):
    return iso(datetime(2026, 10, day, hour, minute, tzinfo=ICT))


def stable_json(obj):
    return json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def generate(blueprint, seed=SEED):
    random.Random(seed)  # Record patterns below are intentionally explicit and reproducible.
    orgs = {o["slug"]: o for o in blueprint["organizations"]}
    assert set(orgs) == {"teamflow-cloud", "novamart-store"}
    tf, nm = orgs["teamflow-cloud"], orgs["novamart-store"]
    assert blueprint["policy_approval"]["status"] == "approved_for_synthetic_demo"
    assert blueprint["policy_version"] == "1.0.0"
    plans = {p["code"]: p for p in tf["plans"]}
    rows = {name: [] for name in (
        "organizations", "users", "memberships", "customers", "tf_workspaces", "tf_subscriptions", "tf_invoices",
        "tf_activation_events", "tf_export_jobs", "tf_api_request_events", "tf_service_incidents",
        "nm_products", "nm_orders", "nm_order_items", "nm_payments", "nm_shipments",
        "nm_shipment_items", "nm_return_requests", "nm_return_items", "nm_warranty_claims"
    )}
    def add(table, **record):
        rows[table].append(record)

    for org in (tf, nm):
        add("organizations", slug=org["slug"], name=org["name"], vertical=org["vertical"], currency=org["currency"], timezone="Asia/Ho_Chi_Minh", default_locale="vi", policy_version="1.0.0")

    for prefix, orgkey in (("tf", "teamflow-cloud"), ("nm", "novamart-store")):
        for role in ("owner", "agent", "viewer"):
            email = f"{prefix}-{role}@example.test"
            add("users", email=email, display_name=f"Synthetic {prefix.upper()} {role}")
            add("memberships", organization=orgkey, email=email, role=role)

    for i in range(1, tf["targets"]["customers"] + 1):
        cust = f"TF-C-{i:03d}"
        ws = f"TF-WS-{i:03d}"
        add("customers", organization="teamflow-cloud", external_key=cust,
            synthetic_email=f"tf-c-{i:03d}@example.test", locale="vi" if i % 2 else "en", display_name=f"Synthetic TeamFlow Customer {i:03d}")
        add("tf_workspaces", organization="teamflow-cloud", workspace_key=ws, customer_key=cust)
        if i == 14:
            effective, requested, status = "free", "pro", "free"
        else:
            effective = ("free", "starter", "pro", "business")[i % 4]
            requested = effective
            status = "free" if effective == "free" else ("past_due" if i % 9 == 0 else "active")
        add("tf_subscriptions", organization="teamflow-cloud", workspace_key=ws,
            plan_code=effective, requested_plan_code=requested, status=status,
            effective_at=stamp(1), renew_at=stamp(30) if status != "free" else None, pending_change_code=None)
        invnums = [f"TF-INV-2026-{(i * 2 - 1):04d}", f"TF-INV-2026-{(i * 2):04d}"]
        if i == 14:
            invnums[0] = "TF-INV-2026-0064"
        if i == 32:  # Reserve 0064 for the established canonical fixture.
            invnums[1] = "TF-INV-2026-1032"
        for seq, number in enumerate(invnums):
            if i == 14 and seq == 0:
                inv_status, price, paid_at = "paid", 6900, stamp(25, 10)
            elif seq == 0 and effective != "free":
                inv_status, price, paid_at = "paid", plans[effective]["monthly_usd"] * 100, stamp(2, 11)
            else:
                inv_status = "pending" if (i + seq) % 2 else "failed"
                price, paid_at = (plans[requested]["monthly_usd"] * 100 if requested != "free" else 0), None
            add("tf_invoices", organization="teamflow-cloud", workspace_key=ws, invoice_number=number,
                total_cents=price, status=inv_status, paid_at=paid_at)
            if seq == 0 and inv_status == "paid":
                succeeded = i != 14
                add("tf_activation_events", organization="teamflow-cloud", workspace_key=ws,
                    invoice_number=number, result="succeeded" if succeeded else "failed",
                    occurred_at=stamp(25, 10, 1) if not succeeded else stamp(2, 11, 1),
                    activated_at=stamp(2, 11, 1) if succeeded else None)

    for i in range(1, tf["targets"]["export_jobs"] + 1):
        ws_idx = (i * 3) % 40 + 1
        add("tf_export_jobs", organization="teamflow-cloud", workspace_key=f"TF-WS-{ws_idx:03d}",
            job_key=f"TF-EXPORT-{i:04d}", status=("queued", "running", "succeeded", "failed")[i % 4],
            error_code="SYNTHETIC_WORKER_TIMEOUT" if i % 4 == 3 else None,
            completed_at=stamp(22) if i % 4 in (2, 3) else None)
    for i in range(1, tf["targets"]["api_request_events"] + 1):
        add("tf_api_request_events", organization="teamflow-cloud", workspace_key=f"TF-WS-{(i * 7) % 40 + 1:03d}",
            request_id=f"TF-REQ-{i:05d}", status_code=429 if i % 11 == 0 else 200,
            route="/v1/projects", occurred_at=stamp(24, 9, i % 60))
    for i in range(1, tf["targets"]["service_incidents"] + 1):
        add("tf_service_incidents", organization="teamflow-cloud", incident_key=f"TF-INC-{i:03d}",
            window_start=stamp(18 + i, 8), window_end=stamp(18 + i, 9) if i % 2 else None,
            affected_components="export-worker" if i % 2 else "api-gateway",
            confirmed_cause="Synthetic queue saturation" if i % 2 else None)

    for i in range(1, nm["targets"]["customers"] + 1):
        add("customers", organization="novamart-store", external_key=f"NM-C-{i:03d}",
            synthetic_email=f"nm-c-{i:03d}@example.test", locale="vi" if i % 2 else "en",
            display_name=f"Synthetic NovaMart Customer {i:03d}")
    for i in range(1, nm["targets"]["products"] + 1):
        category = ("KBD", "MOU", "HOM", "OFF")[(i - 1) % 4]
        sku = "NM-KBD-011" if i == 11 else f"NM-{category}-{i:03d}"
        price = 320000 if i == 11 else (60000 + ((i * 37000) % 750000))
        add("nm_products", organization="novamart-store", sku=sku,
            name=f"Synthetic {category} product {i:03d}", current_price_vnd=price,
            stock=20 + i, warranty_months=12 if i % 4 in (1, 2) else 0, active=True)
    products = rows["nm_products"]
    sku_to_product = {p["sku"]: p for p in products}
    split_indices = set(range(12, 121, 12)) | {42} | {i for i in range(16, 120, 7)}
    # Deterministically choose exactly 20 from the eligible pool, forcing 42.
    split_indices = set(sorted(split_indices - {42})[:19]) | {42}
    assert len(split_indices) == 20 and all(i > 10 for i in split_indices)
    delivered_order_keys = []
    for i in range(1, nm["targets"]["orders"] + 1):
        customer_idx = 31 if i == 42 else ((i - 1) % 60) + 1
        number = f"NM-2026-{i:04d}"
        is_pending = i <= 10
        has_two = (i % 2 == 0 and i != 42) or i == 43
        product_indexes = [11] if i == 42 else [((i * 3) % 40) + 1]
        if has_two:
            product_indexes.append(((i * 3 + 13) % 40) + 1)
        entries = []
        for j, pi in enumerate(product_indexes):
            prod = products[pi - 1]
            quantity = 2 if (i == 42 or (i in split_indices and j == 0)) else (2 if i % 13 == 0 and j == 0 else 1)
            price = 320000 if i == 42 else prod["current_price_vnd"]
            discount = 0 if i == 42 else (10000 if i % 8 == 0 and j == 0 else 0)
            entries.append((prod["sku"], price, quantity, discount))
        subtotal = sum(price * q for _, price, q, _ in entries)
        discount_total = sum(discount for _, _, _, discount in entries)
        shipping = 0 if subtotal - discount_total >= 500000 else 30000
        order_status = "pending_payment" if is_pending else ("shipped" if (i in split_indices or i % 7 == 0) else "delivered")
        add("nm_orders", organization="novamart-store", order_number=number,
            customer_key=f"NM-C-{customer_idx:03d}", status=order_status,
            subtotal_vnd=subtotal, discount_vnd=discount_total, shipping_vnd=shipping,
            grand_total_vnd=subtotal - discount_total + shipping)
        for sku, price, qty, disc in entries:
            add("nm_order_items", organization="novamart-store", order_number=number,
                sku_snapshot=sku, unit_price_snapshot_vnd=price, quantity=qty, discount_snapshot_vnd=disc)
        add("nm_payments", organization="novamart-store", order_number=number,
            payment_key=f"NM-PAY-2026-{i:04d}", amount_vnd=subtotal - discount_total + shipping,
            status="pending" if is_pending else "paid",
            confirmed_at=None if is_pending else stamp(20, 10))
        if is_pending:
            continue
        if i not in split_indices:
            ship_key = f"NM-SHIP-{i:03d}-A"
            shipped_at = stamp(21, 11)
            delivered = order_status == "delivered"
            add("nm_shipments", organization="novamart-store", order_number=number,
                shipment_key=ship_key, carrier_label="SYNTHETIC-CARRIER-A",
                status="delivered" if delivered else "in_transit", shipped_at=shipped_at,
                delivered_at=stamp(23, 15) if delivered else None)
            for sku, _, qty, _ in entries:
                add("nm_shipment_items", organization="novamart-store", shipment_key=ship_key,
                    order_number=number, sku_snapshot=sku, shipped_quantity=qty)
            if delivered:
                delivered_order_keys.append(number)
        else:
            shipped = stamp(26, 9) if i == 42 else stamp(21, 11)
            first_delivered_at = stamp(27, 9) if i == 42 else stamp(23, 15)
            first_key = "NM-SHIP-042-A" if i == 42 else f"NM-SHIP-{i:03d}-A"
            second_key = "NM-SHIP-042-B" if i == 42 else f"NM-SHIP-{i:03d}-B"
            add("nm_shipments", organization="novamart-store", order_number=number,
                shipment_key=first_key, carrier_label="SYNTHETIC-CARRIER-A", status="delivered",
                shipped_at=shipped, delivered_at=first_delivered_at)
            add("nm_shipments", organization="novamart-store", order_number=number,
                shipment_key=second_key, carrier_label="SYNTHETIC-CARRIER-B", status="in_transit",
                shipped_at=stamp(26, 11) if i == 42 else stamp(21, 13), delivered_at=None)
            for j, (sku, _, qty, _) in enumerate(entries):
                if j == 0:
                    add("nm_shipment_items", organization="novamart-store", shipment_key=first_key,
                        order_number=number, sku_snapshot=sku, shipped_quantity=1)
                    add("nm_shipment_items", organization="novamart-store", shipment_key=second_key,
                        order_number=number, sku_snapshot=sku, shipped_quantity=qty - 1)
                else:
                    add("nm_shipment_items", organization="novamart-store", shipment_key=first_key,
                        order_number=number, sku_snapshot=sku, shipped_quantity=qty)
        # Some paid shipped orders are intentionally incomplete for support evaluation.
    assert len(delivered_order_keys) >= 25
    for i, number in enumerate(delivered_order_keys[:25], start=1):
        target = next(r for r in rows["nm_order_items"] if r["order_number"] == number)
        add("nm_return_requests", organization="novamart-store", order_number=number,
            request_key=f"NM-RETURN-{i:04d}", reason="ordinary_return" if i % 3 else "defective_item",
            status="requested" if i % 2 else "under_review", reviewed_by=None)
        add("nm_return_items", organization="novamart-store", request_key=f"NM-RETURN-{i:04d}",
            order_number=number, sku_snapshot=target["sku_snapshot"], quantity=1)
    eligible_claims = [r for r in rows["nm_order_items"] if r["order_number"] in delivered_order_keys
                       and sku_to_product[r["sku_snapshot"]]["warranty_months"] > 0]
    assert len(eligible_claims) >= 12
    for i, item in enumerate(eligible_claims[:12], start=1):
        add("nm_warranty_claims", organization="novamart-store", order_number=item["order_number"],
            sku_snapshot=item["sku_snapshot"], claim_key=f"NM-WARRANTY-{i:04d}",
            status="requested", reviewed_by=None)

    expected = {
        "customers": 100, "tf_workspaces": 40, "tf_subscriptions": 40,
        "tf_invoices": 80, "tf_export_jobs": 35, "tf_api_request_events": 50,
        "tf_service_incidents": 8, "nm_products": 40, "nm_orders": 120,
        "nm_payments": 120, "nm_shipments": 130, "nm_return_requests": 25,
        "nm_warranty_claims": 12,
    }
    for table, count in expected.items():
        assert len(rows[table]) == count, (table, len(rows[table]), count)
    assert len(rows["nm_order_items"]) >= 170
    return {"kind": "M1_DETERMINISTIC_BUSINESS_RECORDS_ONLY", "policy_version": "1.0.0",
            "seed": seed, "reference_time": iso(REF), "schema_version": "1.0",
            "not_included": ["tickets", "KB_full_text", "gold_eval_cases", "AI_inference"], "records": rows}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--blueprint", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    bp_bytes = Path(args.blueprint).read_bytes()
    data = generate(json.loads(bp_bytes))
    output = Path(args.out)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    records = {k: len(v) for k, v in data["records"].items()}
    report = {"status": "GENERATED_OFFLINE_NOT_SEEDED_IN_DB", "seed": data["seed"],
              "reference_time": data["reference_time"], "policy_version": data["policy_version"],
              "blueprint_sha256": hashlib.sha256(bp_bytes).hexdigest(),
              "dataset_sha256": hashlib.sha256(output.read_bytes()).hexdigest(), "counts": records,
              "note": "The records are a deterministic source artifact, not database rows or evaluation gold."}
    output.with_suffix(".manifest.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
