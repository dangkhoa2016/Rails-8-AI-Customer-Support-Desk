#!/usr/bin/env python3
"""Validate human-completed M5.2 review worksheet without generating gold labels.

The baseline CSV remains untouched. Use:
  python3 script/m52_review_intake.py review/m5_independent_120_20261030/BLINDED_REVIEW_WORKSHEET_NOT_GOLD.csv
"""
import argparse
import csv
import hashlib
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "review/m5_independent_120_20261030"
APPROVED = SOURCE / "APPROVED_KB_REFERENCE_ONLY.json"
BLINDED = SOURCE / "BLINDED_REVIEW_TEMPLATE_NOT_GOLD.json"
SOURCE_MANIFEST = SOURCE / "MANIFEST.json"
ALLOWED = {"SUPPORTED", "PARTIAL", "NEEDS_CASE_EVIDENCE", "UNSUPPORTED"}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(path):
    baseline = json.loads(BLINDED.read_text())
    sources = json.loads(APPROVED.read_text())
    manifest = json.loads(SOURCE_MANIFEST.read_text())
    assert manifest["human_gold_cases"] == 0
    assert manifest["files"][APPROVED.name] == sha(APPROVED)
    assert manifest["files"][BLINDED.name] == sha(BLINDED)
    by_id = {c["case_id"]: c for c in baseline["cases"]}
    references = {(a["tenant"], a["locale"], a["article_key"]): a
                  for a in sources["articles"]}
    assert len(by_id) == 120 and len(references) == 12
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        rows = list(csv.DictReader(stream))
    assert len(rows) == 120 and len({r["case_id"] for r in rows}) == 120
    counts = Counter()
    errors = []
    for row in rows:
        case = by_id.get(row["case_id"])
        if case is None or any(row.get(k) != case[k] for k in ("tenant", "locale", "question")):
            errors.append({"case_id": row.get("case_id"), "error": "BASELINE_MISMATCH"})
            continue
        label = row.get("support_label", "").strip()
        status = row.get("review_status", "").strip()
        if status == "NOT_PERFORMED" and not label:
            counts["NOT_PERFORMED"] += 1
            continue
        if status != "APPROVED" or label not in ALLOWED or not row.get("reviewer_id", "").strip():
            errors.append({"case_id": row["case_id"], "error": "INCOMPLETE_HUMAN_ATTESTATION"})
            continue
        key = row.get("evidence_article_key", "").strip()
        digest = row.get("evidence_body_sha256", "").strip()
        ref = references.get((row["tenant"], row["locale"], key))
        if label in {"SUPPORTED", "PARTIAL"} and (ref is None or digest != ref["body_sha256"]):
            errors.append({"case_id": row["case_id"], "error": "INVALID_APPROVED_KB_EVIDENCE"})
            continue
        if label == "NEEDS_CASE_EVIDENCE" and not row.get("missing_case_evidence", "").strip():
            errors.append({"case_id": row["case_id"], "error": "MISSING_CASE_EVIDENCE_NOTE"})
            continue
        if label == "UNSUPPORTED" and not row.get("unsupported_actions", "").strip():
            errors.append({"case_id": row["case_id"], "error": "UNSUPPORTED_REASON_REQUIRED"})
            continue
        counts[label] += 1
    return {"status": "INVALID_REVIEW_ROWS" if errors else "VALID_REVIEW_INPUT_NOT_GOLD",
            "worksheet_sha256": sha(path), "baseline_sha256": sha(BLINDED),
            "approved_sources_sha256": sha(APPROVED), "total": len(rows),
            "human_approved_count": sum(counts[k] for k in ALLOWED),
            "not_reviewed_count": counts["NOT_PERFORMED"],
            "label_counts": {k: counts[k] for k in sorted(ALLOWED)},
            "errors": errors[:20],
            "semantic_gold_promoted": False, "sealed80": "BLOCKED"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("worksheet", type=Path)
    args = parser.parse_args()
    assert args.worksheet.is_file()
    outcome = verify(args.worksheet)
    print(json.dumps(outcome, indent=2, ensure_ascii=False))
    if outcome["errors"]:
        raise SystemExit(2)
