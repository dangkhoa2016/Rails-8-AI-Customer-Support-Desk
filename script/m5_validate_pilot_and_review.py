#!/usr/bin/env python3
"""Read-only, fail-closed validation of M5 pilot, HTTPS and review artifacts."""
from collections import Counter
from pathlib import Path
import hashlib
import json

ROOT=Path(__file__).resolve().parents[1]
DATA=ROOT/"review/m2_dual_qwen3_4b_pilot_queries.json"
PILOT=ROOT/"evidence-m5-live-recovery-20261030/m5-pilot-four-readonly.jsonl"
HTTPS=ROOT/"evidence-m5-live-recovery-20261030/m5-https-ui-four-readonly.jsonl"
HTTPS_RECOVERY=ROOT/"evidence-m5-live-recovery-20261030/m5-https-ui-one-after-preemption-recovery.jsonl"
REVIEW=ROOT/"review/m5_independent_120_20261030"
CANDIDATES=ROOT/"data/m3_support_evaluation_candidates_120.json"
M3=ROOT/"data/m3_synthetic_tickets.json"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def jsonlines(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def main():
    source={row["case_id"]:row for row in json.loads(DATA.read_text())["cases"]}
    ids=["M2-4B-01","M2-4B-02","M2-4B-07","M2-4B-08"]
    assert PILOT.is_file()
    cases=jsonlines(PILOT)
    assert [x["case_id"] for x in cases]==ids
    for row in cases:
        item=source[row["case_id"]]
        assert row["status"]=="PASS_LIVE_AUTHENTICATED_READONLY"
        assert row["top1_matches_source_hint"] is True
        assert row["tenant"]==item["tenant"] and row["locale"]==item["locale"]
        assert row["query_sha256"]==hashlib.sha256(item["query"].encode()).hexdigest()
        assert row["writes"]=="NONE" and row["sealed80"]=="BLOCKED"
        assert row["elapsed_ms"]>0 and row["returned_count"]==len(row["citations"])>0
        assert all(c["article_key"].startswith("TF-" if row["tenant"]=="teamflow-cloud" else "NM-") for c in row["citations"])
        assert all(c["locale"]==row["locale"] and len(c["chunk_sha256"])==64 for c in row["citations"])

    if not HTTPS.is_file():
        https="NOT_RUN"
    else:
        rows=jsonlines(HTTPS)
        assert len(rows) <= len(ids)
        assert [x["case_id"] for x in rows] == ids[:len(rows)]
        for row in rows:
            item=source[row["case_id"]]
            assert row["query_sha256"]==hashlib.sha256(item["query"].encode()).hexdigest()
            assert row["tenant"]==item["tenant"] and row["locale"]==item["locale"]
            assert row["business_writes"]==0
            if row["status"]=="PASS_REAL_MODAL_HTTPS_UI":
                assert row["status_code"]==200 and row["citations_rendered"]>0
                assert row["cross_tenant_hits"]==0 and row["top1_hint_matches"]
            else:
                assert row["status"]=="FAIL_HTTP" and row["status_code"] in (500,502,503,504,520,522,524)
        https=("PASS_4_4" if len(rows)==4 and all(r["status"]=="PASS_REAL_MODAL_HTTPS_UI" for r in rows)
               else ("FAIL_HTTP_"+str(rows[-1]["status_code"]) if rows and rows[-1]["status"]=="FAIL_HTTP"
                     else "PENDING_OR_PARTIAL"))

    recovery="NOT_RUN"
    if HTTPS_RECOVERY.exists():
        recovery_rows=jsonlines(HTTPS_RECOVERY)
        assert len(recovery_rows) <= 1
        for row in recovery_rows:
            assert row["case_id"] == ids[0] and row["business_writes"] == 0
            assert row["query_sha256"] == hashlib.sha256(source[ids[0]]["query"].encode()).hexdigest()
            if row["status"]=="PASS_REAL_MODAL_HTTPS_UI":
                assert row["status_code"]==200 and row["top1_hint_matches"] and row["citations_rendered"]>0
                recovery="PASS_1_1"
            else:
                assert row["status"]=="FAIL_HTTP" and row["status_code"] in (500,502,503,504,520,522,524)
                recovery="FAIL_HTTP_" + str(row["status_code"])

    original=json.loads(CANDIDATES.read_text())
    assert original["semantic_gold"] is False and original["answerability_gate"]=="BLOCKED"
    blind=json.loads((REVIEW/"BLINDED_REVIEW_TEMPLATE_NOT_GOLD.json").read_text())
    manifest=json.loads((REVIEW/"MANIFEST.json").read_text())
    assert len(blind["cases"])==120 and manifest["human_gold_cases"]==0
    assert manifest["independent_human_reviews"]==0
    assert manifest["source_candidate_sha256"]==sha(CANDIDATES)
    assert len(set(x["case_id"] for x in blind["cases"]))==120
    assert Counter(x["tenant"] for x in blind["cases"])=={"teamflow-cloud":40,"novamart-store":80}
    for c in blind["cases"]:
        assert c["review"]["review_status"]=="NOT_PERFORMED" and c["review"]["support_label"] is None
        assert "evaluation_intent_hint" not in c and "expected_article_key" not in c
    for filename,digest in manifest["files"].items():
        assert sha(REVIEW/filename)==digest
    assert sha(M3)=="398e3de1fe231eaa6baabded10183502ed8551f33869c188d534e16bfe2c81fd"
    print(json.dumps({
        "status":"PASS_M5_PILOT_AND_REVIEW_EVIDENCE_VALIDATED",
        "pilot":"PASS_4_4","https_ui":https,"https_recovery":recovery,
        "review_candidates":120,"human_gold":0,"sealed80":"BLOCKED",
        "source_sha256":sha(DATA),"pilot_sha256":sha(PILOT),
        "https_sha256":sha(HTTPS) if HTTPS.is_file() else None,
        "https_recovery_sha256":sha(HTTPS_RECOVERY) if HTTPS_RECOVERY.exists() else None,
        "review_manifest_sha256":sha(REVIEW/"MANIFEST.json"),
        "m3_original_sha256":sha(M3)
    },ensure_ascii=False,indent=2))


if __name__=="__main__":
    main()
