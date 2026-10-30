#!/usr/bin/env python3
"""Create blinded, NOT-GOLD M5.1 review artifacts from approved synthetic snapshots.

Never promote candidate hints to gold labels and never call a model.
"""
import collections
import csv
import hashlib
import json
from io import StringIO
from pathlib import Path
import random

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data/m3_support_evaluation_candidates_120.json"
SOURCE_MANIFEST = ROOT / "data/m3_support_evaluation_candidates_120.manifest.json"
SNAPSHOT = ROOT / "evidence-m2-claim64-provisional-audit-20261029/approved-kb-v2-readonly-snapshot.json"
OUTPUT_DIR = ROOT / "review/m5_independent_120_20261030"
SHUFFLE_SEED = 20261030


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def write_new(path, payload):
    if path.exists():
        raise RuntimeError(f"Refuse overwrite of {path.name}")
    path.write_bytes(payload)


def canonical(obj):
    return (json.dumps(obj, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")


def main():
    raw = json.loads(SOURCE.read_text())
    manifest = json.loads(SOURCE_MANIFEST.read_text())
    reference = json.loads(SNAPSHOT.read_text())
    assert raw["semantic_gold"] is False and raw["answerability_gate"] == "BLOCKED"
    assert sha(SOURCE) == manifest["dataset_sha256"]
    assert sha(SNAPSHOT) == raw["source_snapshot_sha256"]
    assert sha(ROOT / "data/m3_synthetic_tickets.json") == raw["source_m3_sha256"]
    assert len(raw["cases"]) == 120 and len(reference["articles"]) == 12
    pairs = {(a["tenant"], a["locale"], a["article_key"]): a for a in reference["articles"]}
    assert len(pairs) == 12
    for a in reference["articles"]:
        assert hashlib.sha256(a["body"].encode()).hexdigest() == a["body_sha256"]
        assert a["article_version_number"] == 2

    blinded = []
    for c in raw["cases"]:
        assert c["gold_answer"] is None and c["independent_human_review"] == "NOT_PERFORMED"
        doc = pairs[c["tenant"], c["locale"], c["source_article_key"]]
        assert doc["body_sha256"] == c["source_approved_body_sha256"]
        blinded.append({
            "case_id": c["case_id"], "tenant": c["tenant"], "locale": c["locale"],
            "question": c["question"],
            # No source_article_key, scenario, model output, or evaluation_intent_hint.
            "review": {
                "reviewer_id": None, "reviewed_utc": None,
                "support_label": None,  # SUPPORTED / PARTIAL / NEEDS_CASE_EVIDENCE / UNSUPPORTED
                "claims": [],
                "approved_kb_evidence": [],  # [{article_key,version,body_sha256,quoted_span}]
                "missing_case_evidence": [], "unsupported_requested_actions": [],
                "safe_human_support_response": None,
                "notes": None,
                "review_status": "NOT_PERFORMED"
            }
        })
    random.Random(SHUFFLE_SEED).shuffle(blinded)
    ids = [c["case_id"] for c in blinded]
    assert len(set(ids)) == 120
    counts = collections.Counter((c["tenant"], c["locale"]) for c in blinded)
    assert counts == {("teamflow-cloud", "vi"): 20, ("teamflow-cloud", "en"): 20,
                      ("novamart-store", "vi"): 40, ("novamart-store", "en"): 40}
    source_m5 = {
        "kind": "M5_BLINDED_REVIEW_TEMPLATE_V1_NOT_GOLD",
        "status": "AWAITING_INDEPENDENT_HUMAN_ANNOTATION",
        "source_candidates_sha256": sha(SOURCE),
        "source_approved_kb_snapshot_sha256": sha(SNAPSHOT),
        "shuffle_seed": SHUFFLE_SEED,
        "cases": blinded, "gold_labels_present": False
    }
    reference_pack = {
        "kind": "M5_APPROVED_KB_READONLY_REFERENCE",
        "status": "SOURCE_SNAPSHOT_NOT_INDEPENDENT_GROUND_TRUTH",
        "source_approved_kb_snapshot_sha256": sha(SNAPSHOT),
        "policy_verification": "M0 approved v1.0.0 (synthetic)",
        "articles": sorted(reference["articles"],key=lambda a:(a["tenant"],a["locale"],a["article_key"]))
    }
    buf = StringIO(newline="")
    out = csv.writer(buf)
    out.writerow(["case_id","tenant","locale","question","support_label","evidence_article_key",
                  "evidence_body_sha256","required_claims","missing_case_evidence","unsupported_actions",
                  "safe_human_support_response","reviewer_id","review_status"])
    for c in blinded:
        out.writerow([c["case_id"],c["tenant"],c["locale"],c["question"]]+[""]*8+["NOT_PERFORMED"])
    # Avoid a misleading future claim: this TSV/CSV is intentionally empty of human labels.
    rows = buf.getvalue().encode("utf-8-sig")
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    items = {
        "BLINDED_REVIEW_TEMPLATE_NOT_GOLD.json": canonical(source_m5),
        "APPROVED_KB_REFERENCE_ONLY.json": canonical(reference_pack),
        "BLINDED_REVIEW_WORKSHEET_NOT_GOLD.csv": rows,
    }
    for name, data in items.items():
        write_new(OUTPUT_DIR / name, data)
    report = {
        "kind": "M5_REVIEW_INPUT_MANIFEST",
        "status": "PREPARED_NOT_REVIEWED",
        "case_count": 120, "approved_kb_references": 12,
        "independent_human_reviews": 0,
        "human_gold_cases": 0,
        "language_counts": {f"{o}:{l}":v for (o,l),v in sorted(counts.items())},
        "shuffle_seed": SHUFFLE_SEED,
        "source_candidate_sha256": sha(SOURCE),
        "source_manifest_sha256": sha(SOURCE_MANIFEST),
        "source_approved_kb_sha256": sha(SNAPSHOT),
        "files": {name:hashlib.sha256(data).hexdigest() for name,data in sorted(items.items())},
        "sealed80": "BLOCKED", "gpu_calls": 0, "db_writes": 0
    }
    write_new(OUTPUT_DIR / "MANIFEST.json",canonical(report))
    print(json.dumps({"status":"PASS_M5_1_BLINDED_REVIEW_INPUTS_PREPARED_NOT_GOLD",
        "cases":120,"KB_sources":12,"human_reviews":0,
        "manifest_sha256":sha(OUTPUT_DIR/"MANIFEST.json"),
        "source_candidates_sha256":sha(SOURCE)},sort_keys=True))


if __name__ == "__main__":
    main()
