#!/usr/bin/env python3
"""Offline deterministic data graph verifier; NOT a Rails/PostgreSQL test."""
import argparse
from collections import Counter, defaultdict
from datetime import datetime
import hashlib
import json
import sqlite3
from pathlib import Path


def must(cond, detail):
    if not cond:
        raise AssertionError(detail)


def lookup(records, table, *fields):
    result = {}
    for r in records[table]:
        k = tuple(r[f] for f in fields)
        must(k not in result, f"duplicate natural key {table}/{k}")
        result[k] = r
    return result


def check(data, blueprint):
    must(data["policy_version"] == blueprint["policy_version"], "policy version mismatch")
    must(data["seed"] == 20261028, "seed mismatch")
    r = data["records"]
    t = {o["slug"]: o for o in blueprint["organizations"]}
    tf, nm = t["teamflow-cloud"], t["novamart-store"]
    must(len(r["organizations"]) == 2, "organization count")
    for table, k in (("customers", "customers"), ("tf_workspaces", "workspaces"),
                     ("tf_subscriptions", "subscriptions"), ("tf_invoices", "invoices"),
                     ("tf_export_jobs", "export_jobs"), ("tf_api_request_events", "api_request_events"),
                     ("tf_service_incidents", "service_incidents")):
        expected = tf["targets"][k]
        actual = sum(x["organization"] == "teamflow-cloud" for x in r[table])
        if table == "customers":
            actual = sum(x["organization"] == "teamflow-cloud" for x in r[table])
        must(actual == expected, f"{table} {actual} != {expected}")
    for table, k in (("customers", "customers"), ("nm_products", "products"),
                     ("nm_orders", "orders"), ("nm_payments", "payments"),
                     ("nm_shipments", "shipments"), ("nm_return_requests", "return_requests"),
                     ("nm_warranty_claims", "warranty_claims")):
        actual = sum(x["organization"] == "novamart-store" for x in r[table])
        must(actual == nm["targets"][k], f"{table} count {actual}")
    must(len(r["nm_order_items"]) >= nm["targets"]["order_items_min"], "order item count")
    keydefs = {"users": ("email",), "memberships": ("organization", "email"),
               "customers": ("organization", "external_key"),
               "tf_workspaces": ("organization", "workspace_key"),
               "tf_subscriptions": ("organization", "workspace_key"),
               "tf_invoices": ("organization", "invoice_number"),
               "tf_activation_events": ("organization", "invoice_number", "result"),
               "tf_export_jobs": ("organization", "job_key"),
               "tf_api_request_events": ("organization", "request_id"),
               "tf_service_incidents": ("organization", "incident_key"),
               "nm_products": ("organization", "sku"),
               "nm_orders": ("organization", "order_number"),
               "nm_order_items": ("organization", "order_number", "sku_snapshot"),
               "nm_payments": ("organization", "payment_key"),
               "nm_shipments": ("organization", "shipment_key"),
               "nm_shipment_items": ("organization", "shipment_key", "sku_snapshot"),
               "nm_return_requests": ("organization", "request_key"),
               "nm_return_items": ("organization", "request_key", "sku_snapshot"),
               "nm_warranty_claims": ("organization", "claim_key")}
    maps = {table: lookup(r, table, *fields) for table, fields in keydefs.items()}
    must(len(r["users"]) == 6 and len(r["memberships"]) == 6, "synthetic demo membership count")
    emails = {x["email"] for x in r["users"]}
    for m in r["memberships"]:
        must(m["email"] in emails and m["organization"] in t and m["role"] in ("owner", "agent", "viewer"), "membership reference/role")
    cust, work, subs, invoice = (maps[k] for k in ("customers", "tf_workspaces", "tf_subscriptions", "tf_invoices"))
    orders, items, pay, ships, shipitems = (maps[k] for k in ("nm_orders", "nm_order_items", "nm_payments", "nm_shipments", "nm_shipment_items"))
    products = maps["nm_products"]
    for w in r["tf_workspaces"]:
        must((w["organization"], w["customer_key"]) in cust, "orphan TF customer")
    for s in r["tf_subscriptions"]:
        must((s["organization"], s["workspace_key"]) in work, "orphan TF subscription workspace")
        must(s["plan_code"] in {"free", "starter", "pro", "business"}, "unknown plan")
        if s["status"] == "free":
            must(s["plan_code"] == "free", "free status mismatch")
    for inv in r["tf_invoices"]:
        must((inv["organization"], inv["workspace_key"]) in subs, "orphan TF invoice")
        must(inv["total_cents"] >= 0, "negative invoice")
        must((inv["status"] == "paid") == (inv["paid_at"] is not None), "TF paid_at mismatch")
    for ev in r["tf_activation_events"]:
        v = invoice[(ev["organization"], ev["invoice_number"])]
        must(v["workspace_key"] == ev["workspace_key"], "activation on wrong subscription")
        must(v["status"] == "paid", "activation for unpaid invoice")
        must((ev["result"] == "succeeded") == (ev["activated_at"] is not None), "activation result/time")
        must(datetime.fromisoformat(ev["occurred_at"]) >= datetime.fromisoformat(v["paid_at"]), "activation before paid")
    for job in r["tf_export_jobs"]:
        must((job["organization"], job["workspace_key"]) in work, "orphan export job")
    for req in r["tf_api_request_events"]:
        must((req["organization"], req["workspace_key"]) in work, "orphan request event")
    for ord_ in r["nm_orders"]:
        must((ord_["organization"], ord_["customer_key"]) in cust, "order customer mismatch")
        its = [x for x in r["nm_order_items"] if x["order_number"] == ord_["order_number"]]
        must(bool(its), "empty order")
        subtotal = sum(x["quantity"] * x["unit_price_snapshot_vnd"] for x in its)
        discount = sum(x["discount_snapshot_vnd"] for x in its)
        must(all(0 <= x["discount_snapshot_vnd"] <= x["quantity"] * x["unit_price_snapshot_vnd"] and x["quantity"] > 0 for x in its), "item money invalid")
        must(ord_["subtotal_vnd"] == subtotal and ord_["discount_vnd"] == discount, "snapshot totals inconsistent")
        must(ord_["shipping_vnd"] == (0 if subtotal - discount >= 500_000 else 30_000), "shipping threshold")
        must(ord_["grand_total_vnd"] == subtotal - discount + ord_["shipping_vnd"], "grand total")
        matches = [p for p in r["nm_payments"] if p["order_number"] == ord_["order_number"]]
        must(len(matches) == 1 and matches[0]["amount_vnd"] == ord_["grand_total_vnd"], "payment amount count")
        must((matches[0]["status"] == "paid") == (ord_["status"] != "pending_payment"), "prepaid fulfillment")
        must((matches[0]["status"] == "paid") == (matches[0]["confirmed_at"] is not None), "paid timestamp")
    shipped = defaultdict(int)
    delivered = defaultdict(int)
    for si in r["nm_shipment_items"]:
        s = ships[(si["organization"], si["shipment_key"])]
        must(s["order_number"] == si["order_number"], "cross-order shipment item")
        ik = (si["organization"], si["order_number"], si["sku_snapshot"])
        must(ik in items and si["shipped_quantity"] > 0, "orphan or non-positive shipment item")
        shipped[ik] += si["shipped_quantity"]
        if s["status"] == "delivered":
            must(s["delivered_at"] is not None, "delivered shipment without date")
            delivered[ik] += si["shipped_quantity"]
        must(s["shipped_at"] is not None and datetime.fromisoformat(s["shipped_at"]) <= datetime.fromisoformat(s["delivered_at"] or data["reference_time"]), "shipment event timeline")
    for ik, it in items.items():
        must(shipped[ik] <= it["quantity"], "overshipped item")
    for o in r["nm_orders"]:
        relevant = [k for k in items if k[1] == o["order_number"]]
        all_delivered = all(delivered[k] == items[k]["quantity"] for k in relevant)
        if o["status"] == "delivered":
            must(all_delivered, "order delivered despite incomplete items")
        if o["status"] == "pending_payment":
            must(not any(s["order_number"] == o["order_number"] for s in r["nm_shipments"]), "unpaid shipment")
    for rr in r["nm_return_requests"]:
        must((rr["organization"], rr["order_number"]) in orders, "orphan return")
        if rr["status"] in ("approved", "refunded"):
            must(rr["reviewed_by"] is not None, "auto-approved return")
    for ri in r["nm_return_items"]:
        rr = maps["nm_return_requests"][(ri["organization"], ri["request_key"])]
        it = items[(ri["organization"], ri["order_number"], ri["sku_snapshot"])]
        must(rr["order_number"] == ri["order_number"] and 0 < ri["quantity"] <= it["quantity"], "invalid return item")
    for wc in r["nm_warranty_claims"]:
        it = items[(wc["organization"], wc["order_number"], wc["sku_snapshot"])]
        must(products[(wc["organization"], it["sku_snapshot"])]["warranty_months"] > 0, "nonwarranty claim")
        must(wc["status"] == "requested" and wc["reviewed_by"] is None, "automatic warranty action")
    reference = invoice[("teamflow-cloud", "TF-INV-2026-0064")]
    refsub = subs[("teamflow-cloud", "TF-WS-014")]
    must(reference["status"] == "paid" and refsub["plan_code"] == "free" and refsub["requested_plan_code"] == "pro", "TF reference discrepancy")
    must(any(e["invoice_number"] == "TF-INV-2026-0064" and e["result"] == "failed" for e in r["tf_activation_events"]), "TF reference activation")
    order42 = orders[("novamart-store", "NM-2026-0042")]
    must(order42["grand_total_vnd"] == 640_000 and order42["shipping_vnd"] == 0, "NM reference totals")
    must(delivered[("novamart-store", "NM-2026-0042", "NM-KBD-011")] == 1, "NM delivered reference")
    must(shipped[("novamart-store", "NM-2026-0042", "NM-KBD-011")] == 2, "NM shipped reference")

    # An independent SQLite relational check uses composite keys to emulate tenant-safe edges.
    # It does NOT certify PostgreSQL or Rails constraints.
    con = sqlite3.connect(":memory:")
    con.execute("PRAGMA foreign_keys=ON")
    con.executescript("""
    CREATE TABLE org(slug TEXT PRIMARY KEY);
    CREATE TABLE customer(org TEXT NOT NULL, key TEXT NOT NULL, PRIMARY KEY(org,key), FOREIGN KEY(org) REFERENCES org(slug));
    CREATE TABLE orders(org TEXT NOT NULL, key TEXT NOT NULL, customer TEXT NOT NULL,
      PRIMARY KEY(org,key), FOREIGN KEY(org,customer) REFERENCES customer(org,key));
    CREATE TABLE item(org TEXT NOT NULL, order_key TEXT NOT NULL, sku TEXT NOT NULL,
      PRIMARY KEY(org,order_key,sku), FOREIGN KEY(org,order_key) REFERENCES orders(org,key));
    CREATE TABLE shipment(org TEXT NOT NULL, key TEXT NOT NULL, order_key TEXT NOT NULL,
      PRIMARY KEY(org,key), FOREIGN KEY(org,order_key) REFERENCES orders(org,key));
    CREATE TABLE shipment_item(org TEXT NOT NULL, shipment_key TEXT NOT NULL, order_key TEXT NOT NULL, sku TEXT NOT NULL,
      PRIMARY KEY(org,shipment_key,sku), FOREIGN KEY(org,shipment_key) REFERENCES shipment(org,key),
      FOREIGN KEY(org,order_key,sku) REFERENCES item(org,order_key,sku));
    """)
    con.executemany("INSERT INTO org VALUES(?)", [(o["slug"],) for o in r["organizations"]])
    con.executemany("INSERT INTO customer VALUES(?,?)", [(x["organization"],x["external_key"]) for x in r["customers"]])
    con.executemany("INSERT INTO orders VALUES(?,?,?)", [(x["organization"],x["order_number"],x["customer_key"]) for x in r["nm_orders"]])
    con.executemany("INSERT INTO item VALUES(?,?,?)", [(x["organization"],x["order_number"],x["sku_snapshot"]) for x in r["nm_order_items"]])
    con.executemany("INSERT INTO shipment VALUES(?,?,?)", [(x["organization"],x["shipment_key"],x["order_number"]) for x in r["nm_shipments"]])
    con.executemany("INSERT INTO shipment_item VALUES(?,?,?,?)", [(x["organization"],x["shipment_key"],x["order_number"],x["sku_snapshot"]) for x in r["nm_shipment_items"]])
    must(con.execute("PRAGMA foreign_key_check").fetchall() == [], "SQLite FK check")
    isolation_negative_test = "NOT_RUN"
    try:
        con.execute("INSERT INTO orders VALUES(?,?,?)", ("novamart-store", "CROSS-TENANT-FORGED", "TF-C-014"))
    except sqlite3.IntegrityError:
        isolation_negative_test = "EXPECTED_REJECTION_SQLITE_ONLY"
    must(isolation_negative_test == "EXPECTED_REJECTION_SQLITE_ONLY", "cross-tenant forged key permitted")
    con.close()
    return {"status": "PASS_OFFLINE_ONLY", "counts": {k: len(v) for k,v in r.items()},
            "checks": ["target counts", "natural key uniqueness", "cross-reference graph", "invoice activation linkage",
                       "money snapshots", "prepaid fulfillment", "split shipment", "return and warranty", "reference fixtures",
                       "SQLite composite FK emulation", "SQLite forged foreign key rejection"],
            "sqlite_tenant_negative_test": isolation_negative_test,
            "rails_postgresql_migrations": "NOT_RUN", "rails_authz": "NOT_RUN"}


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--blueprint",required=True)
    ap.add_argument("--dataset",required=True)
    ap.add_argument("--report",required=True)
    a=ap.parse_args()
    d=json.loads(Path(a.dataset).read_text())
    b=json.loads(Path(a.blueprint).read_text())
    report=check(d,b)
    report["dataset_sha256"]=hashlib.sha256(Path(a.dataset).read_bytes()).hexdigest()
    report["blueprint_sha256"]=hashlib.sha256(Path(a.blueprint).read_bytes()).hexdigest()
    Path(a.report).parent.mkdir(parents=True,exist_ok=True)
    Path(a.report).write_text(json.dumps(report,ensure_ascii=False,indent=2,sort_keys=True)+"\n")
    print(json.dumps(report,indent=2))

if __name__=="__main__": main()
