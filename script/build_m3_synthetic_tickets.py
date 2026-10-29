#!/usr/bin/env python3
"""Build M3 synthetic-only ticket snapshots from the immutable M1 business dataset."""
from __future__ import annotations

import collections
import datetime as dt
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
M1 = ROOT / "data/m1_business_records.json"
M3 = ROOT / "data/m3_synthetic_tickets.json"
MANIFEST = ROOT / "data/m3_synthetic_tickets.manifest.json"
SEED = 20261029
TZ = dt.timezone(dt.timedelta(hours=7))
START = dt.datetime(2026, 10, 28, 8, 0, tzinfo=TZ)
COUNTS = {
    "teamflow-cloud": {
        "billing_subscription": ("invoice", 36),
        "permissions_workspace": ("workspace", 20),
        "exports_jobs": ("export", 20),
        "integrations_api": ("api", 20),
        "incidents_bugs": ("incident", 12),
        "general_howto": ("subscription", 12),
    },
    "novamart-store": {
        "order_status": ("order", 24),
        "payment_issues": ("payment", 20),
        "shipping_exceptions": ("shipment", 24),
        "returns_refunds": ("return", 24),
        "product_warranty": ("warranty", 12),
        "missing_wrong_damaged": ("order", 16),
    },
}
STATUSES = ("new", "open", "pending_customer", "pending_internal", "resolved", "closed")
AGENTS = {"teamflow-cloud": "tf-agent@example.test", "novamart-store": "nm-agent@example.test"}

def canonical(payload):
    return (json.dumps(payload, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode()

def fingerprint(data):
    return hashlib.sha256(data).hexdigest()

def source_records(rows, org):
    customers = {c["external_key"]: c for c in rows["customers"] if c["organization"] == org}
    workspaces = {w["workspace_key"]: w["customer_key"] for w in rows["tf_workspaces"]}
    orders = {o["order_number"]: o["customer_key"] for o in rows["nm_orders"]}
    result = collections.defaultdict(list)
    sources = (
        ("invoice", "tf_invoices", "invoice_number", "workspace_key"),
        ("workspace", "tf_workspaces", "workspace_key", "workspace_key"),
        ("export", "tf_export_jobs", "job_key", "workspace_key"),
        ("api", "tf_api_request_events", "request_id", "workspace_key"),
        ("subscription", "tf_subscriptions", "workspace_key", "workspace_key"),
        ("incident", "tf_service_incidents", "incident_key", None),
        ("order", "nm_orders", "order_number", "order_number"),
        ("payment", "nm_payments", "payment_key", "order_number"),
        ("shipment", "nm_shipments", "shipment_key", "order_number"),
        ("return", "nm_return_requests", "request_key", "order_number"),
        ("warranty", "nm_warranty_claims", "claim_key", "order_number"),
    )
    for kind, table, key, join_key in sources:
        for row in rows[table]:
            if row["organization"] != org:
                continue
            if join_key is None:
                customer_key = None
            elif org == "teamflow-cloud":
                customer_key = workspaces[row[join_key]]
            else:
                customer_key = orders[row[join_key]]
            ref = row[key]
            fact_keys = ("status", "result", "paid_at", "confirmed_at", "occurred_at",
                         "shipped_at", "delivered_at", "total_cents", "grand_total_vnd",
                         "route", "status_code", "error_code", "window_start")
            facts = {k: row[k] for k in fact_keys if row.get(k) is not None}
            result[kind].append({"kind": kind, "reference": ref, "customer_key": customer_key,
                                 "facts": facts, "source_table": table})
    return result, customers

def message_text(kind, ref, facts, locale):
    status = facts.get("status", facts.get("result", "unknown"))
    if locale == "vi":
        customer = {
            "invoice": f"Hóa đơn {ref} hiện ghi nhận trạng thái {status}. Nhờ kiểm tra thanh toán, kích hoạt gói và sự kiện liên quan trước khi kết luận.",
            "workspace": f"Tôi cần xác minh quyền truy cập và trạng thái workspace {ref}. Xin hướng dẫn những bước kiểm tra cần thiết.",
            "subscription": f"Tôi muốn đối chiếu gói hiện tại cho workspace {ref}. Xin kiểm tra dữ liệu subscription trước khi tư vấn.",
            "export": f"Tác vụ xuất dữ liệu {ref} đang có trạng thái {status}. Xin kiểm tra log và tiến trình xử lý.",
            "api": f"Xin kiểm tra request {ref} (HTTP {facts.get('status_code', 'n/a')}) và hướng dẫn bước chẩn đoán phù hợp.",
            "incident": f"Tôi muốn biết incident {ref} có liên quan đến vấn đề đã gặp không. Xin đối chiếu thời gian và phạm vi ảnh hưởng.",
            "order": f"Đơn hàng {ref} đang hiển thị {status}. Xin kiểm tra tình trạng và các bước tiếp theo.",
            "payment": f"Giao dịch {ref} có trạng thái {status}. Xin xác minh với đơn hàng trước khi đưa ra kết luận thanh toán.",
            "shipment": f"Lô giao hàng {ref} hiển thị {status}. Xin đối chiếu tiến độ và tình trạng giao từng phần.",
            "return": f"Yêu cầu trả hàng {ref} đang ở trạng thái {status}. Xin cho biết hồ sơ cần được kiểm tra thêm.",
            "warranty": f"Yêu cầu bảo hành {ref} đang ở trạng thái {status}. Xin xác minh điều kiện và bằng chứng liên quan.",
        }[kind]
        note = f"Chỉ là dữ liệu synthetic. Kiểm tra bản ghi gốc {ref}, chính sách KB đã duyệt và tình tiết còn thiếu; không tự duyệt hoàn tiền, kích hoạt hoặc cam kết với khách."
    else:
        customer = {
            "invoice": f"Invoice {ref} currently shows {status}. Please verify payment, activation events, and current entitlements before concluding.",
            "workspace": f"Please help verify access and account context for workspace {ref} before advising on a change.",
            "subscription": f"I need a check of the current subscription for workspace {ref} before any recommendation.",
            "export": f"Export job {ref} currently shows {status}. Please inspect the job evidence and progress.",
            "api": f"Please investigate request {ref} (HTTP {facts.get('status_code', 'n/a')}) and suggest diagnostic steps.",
            "incident": f"Could incident {ref} relate to my issue? Please check the timeline and affected components.",
            "order": f"Order {ref} currently shows {status}. Could you review its state and next steps?",
            "payment": f"Payment {ref} currently shows {status}. Please compare it against the order before confirming anything.",
            "shipment": f"Shipment {ref} currently shows {status}. Please check progress and partial-delivery evidence.",
            "return": f"Return request {ref} currently shows {status}. Please identify what evidence must be reviewed.",
            "warranty": f"Warranty claim {ref} currently shows {status}. Please verify eligibility and supporting facts.",
        }[kind]
        note = f"Synthetic-only triage. Check original record {ref}, approved KB, and missing case facts; never auto-approve refunds, activation, or customer commitments."
    return customer, note

def uuid_for(number, n):
    h = hashlib.sha256(f"M3:{SEED}:{number}:message:{n}".encode()).hexdigest()[:32]
    return f"{h[:8]}-{h[8:12]}-4{h[13:16]}-a{h[17:20]}-{h[20:32]}"

def build():
    original = M1.read_bytes()
    m1 = json.loads(original)
    assert m1["kind"] == "M1_DETERMINISTIC_BUSINESS_RECORDS_ONLY"
    rows = m1["records"]
    tickets = []
    for org, categories in COUNTS.items():
        catalogs, customers = source_records(rows, org)
        remaining = {category: count for category, (_, count) in categories.items()}
        schedule = []
        # Each business scenario has a paired VI and EN case; preserve category
        # balance too, instead of only balancing language at the tenant level.
        while any(remaining.values()):
            for category in categories:
                if remaining[category]:
                    assert remaining[category] >= 2
                    schedule.extend((category, category))
                    remaining[category] -= 2
        assert len(schedule) == 120
        selection_counters = collections.Counter()
        org_tickets = []
        for n, category in enumerate(schedule):
            kind = categories[category][0]
            locale = ("vi", "en")[n % 2]
            pool = [s for s in catalogs[kind] if
                    s["customer_key"] is None or customers[s["customer_key"]]["locale"] == locale]
            assert pool, (org, kind, locale)
            counter_key = (category, locale)
            source = pool[selection_counters[counter_key] % len(pool)]
            selection_counters[counter_key] += 1
            if source["customer_key"] is None:
                customer_pool = sorted(c for c in customers if customers[c]["locale"] == locale)
                customer_key = customer_pool[n % len(customer_pool)]
            else:
                customer_key = source["customer_key"]
            assert customers[customer_key]["locale"] == locale
            number = ("TF" if org == "teamflow-cloud" else "NM") + f"-M3-{n + 1:04d}"
            opened = START + dt.timedelta(minutes=n * 6)
            # Adjacent VI/EN cases have the same workflow distribution; avoid
            # accidentally coupling lifecycle status or urgency to language.
            status = STATUSES[(n // 2) % len(STATUSES)]
            band = (n // 2) % 12
            priority = "P1" if band == 0 else "P2" if band in (1, 4, 7) else "P4" if band in (3, 9) else "P3"
            text, note = message_text(kind, source["reference"], source["facts"], locale)
            messages = [{"actor_type": "customer", "visibility": "public", "body": text,
                         "channel": "synthetic_seed", "sent_at": opened.isoformat(),
                         "idempotency_key": uuid_for(number, 0)}]
            if status != "new":
                messages.append({"actor_type": "agent", "visibility": "internal", "body": note,
                                 "channel": "synthetic_seed",
                                 "sent_at": (opened + dt.timedelta(minutes=15)).isoformat(),
                                 "idempotency_key": uuid_for(number, 1)})
            updated = max(dt.datetime.fromisoformat(m["sent_at"]) for m in messages)
            org_tickets.append({
                "organization": org, "customer_key": customer_key, "locale": locale,
                "number": number, "category": category, "priority": priority,
                "status": status, "assignee_email": AGENTS[org],
                "business_ref": source["reference"],
                "source_table": source["source_table"], "source_kind": kind,
                "source_facts": source["facts"], "synthetic": True,
                "ai_generated": False, "human_policy_gold": None,
                "created_at": opened.isoformat(), "updated_at": updated.isoformat(),
                "messages": messages,
            })
        assert all(v == 0 for v in remaining.values()), remaining
        tickets.extend(org_tickets)
    dataset = {"kind": "M3_SYNTHETIC_SUPPORT_TICKETS_V1", "seed": SEED,
               "reference_time": "2026-10-29T00:00:00+07:00",
               "policy_version": "1.0.0", "source_m1_sha256": fingerprint(original),
               "approval_basis": "SYNTHETIC_DEMO_ONLY_NOT_SEMANTIC_GOLD",
               "ai_business_writes": "PROHIBITED", "human_approval_required": True,
               "tickets": tickets}
    raw = canonical(dataset)
    manifest = {"kind": "M3_SYNTHETIC_TICKETS_MANIFEST_V1", "seed": SEED,
                "dataset_path": "data/m3_synthetic_tickets.json",
                "dataset_sha256": fingerprint(raw),
                "source_m1_sha256": fingerprint(original),
                "ticket_count": len(tickets),
                "message_count": sum(len(t["messages"]) for t in tickets),
                "counts_by_tenant": dict(collections.Counter(t["organization"] for t in tickets)),
                "counts_by_tenant_locale": dict(collections.Counter(
                    t["organization"] + ":" + t["locale"] for t in tickets)),
                "source_approved_for_demo_only": True,
                "not_a_semantic_gold_dataset": True,
                "existing_sealed80_scope_gate": "BLOCKED",
                "db_import_execution": "NOT_RUN"}
    for path, data in ((M3, raw), (MANIFEST, canonical(manifest))):
        if path.exists() and path.read_bytes() != data:
            raise RuntimeError(f"Refusing to overwrite an existing different artifact: {path}")
        path.write_bytes(data)
    print(json.dumps({"result": "M3_DATASET_GENERATED", **manifest}, indent=2))

if __name__ == "__main__":
    build()
