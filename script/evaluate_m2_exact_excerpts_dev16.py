#!/usr/bin/env python3
"""Score one frozen 16-query development run; no repair or thresholds fitted."""
import collections
import hashlib
import json
from pathlib import Path
import statistics
import sys
import time
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"script"))
from m2_deterministic_exact_spans import recover,SpanRejected

MANIFEST=ROOT/"review/m2_exact_excerpt_development16_20261029.json"
RESULTS=ROOT/"evidence-m2-exact-excerpts-dev16-20261029/exact-excerpt-live.json"
OUTPUT=ROOT/"evidence-m2-exact-excerpts-dev16-20261029/dev16-evaluation.json"
SHA_MANIFEST="380de3f24ddc765cb7e3545b2d03dd8f66535918c79fd85614bcddedcfac5f11"
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert not OUTPUT.exists(),"Never overwrite post-inference evidence"
assert sha(MANIFEST)==SHA_MANIFEST
m=json.loads(MANIFEST.read_text())
r=json.loads(RESULTS.read_text())
assert r["model_id"]==m["model_id"] and r["model_revision"]==m["model_revision"]
assert len(m["cases"])==len(r["cases"])==16
byid={c['id']:c for c in m["cases"]}
assert len(byid)==16
case_ids=set()
evaluations=[]
for case in r["cases"]:
    assert case["id"] in byid and case["id"] not in case_ids
    case_ids.add(case["id"])
    source=byid[case["id"]]
    assert (case["tenant"],case["locale"])==(source["tenant"],source["locale"])
    assert case["question_sha256"]==hashlib.sha256(source["question"].encode()).hexdigest()
    passed=False
    reason=None
    resolved=None
    if not isinstance(case["parsed"],dict):
        reason="INVALID_JSON_OR_NONOBJECT_NO_REPAIR"
    else:
        try:
            resolved=recover(source["question"],case["parsed"],
                            tenant=source["tenant"],locale=source["locale"])
            passed=True
        except (SpanRejected,KeyError,TypeError) as err:
            reason=str(err)[:160]
    intent_count=len(resolved["claims"]) if passed else None
    unresolved_count=len(resolved["unresolved"]) if passed else None
    meets_minimum=bool(passed and intent_count>=source["expected_min_intents"])
    fully_mapped=bool(meets_minimum and unresolved_count==0)
    evaluations.append({
        "id":case["id"],"tenant":case["tenant"],"locale":case["locale"],
        "question_sha256":case["question_sha256"],
        "parse_status":case["parse_status"],
        "json_object_parsed":isinstance(case["parsed"],dict),
        "exact_source_spans_pass":passed,
        "exact_source_failure":reason,
        "claims_count":intent_count,
        "developer_expected_min_intents":source["expected_min_intents"],
        "minimum_intents_recovered":meets_minimum,
        "fully_mapped_without_unresolved":fully_mapped,
        "uncertain_parts":unresolved_count,
        "recovered":resolved,
        "generation_seconds":case["generation_seconds"],
        "generated_tokens":case["generated_tokens"]
    })
assert len(evaluations)==16
labels=collections.defaultdict(list)
for e in evaluations:labels[e['tenant']+'/'+e['locale']].append(e)
by_stratum={name:{
    "total":len(rows),
    "parseable_json":sum(e["json_object_parsed"] for e in rows),
    "exact_source_spans_pass":sum(e["exact_source_spans_pass"] for e in rows),
    "minimum_intents_recovered":sum(e["minimum_intents_recovered"] for e in rows),
    "fully_mapped_without_unresolved":sum(e["fully_mapped_without_unresolved"] for e in rows)
} for name,rows in sorted(labels.items())}
times=[x["generation_seconds"] for x in evaluations]
summary={
    "kind":"M2_EXACT_EXCERPT_DEVELOPMENT16_QWEN3_A10_EVALUATION",
    "status":"DEVELOPMENT_ONLY_NOT_SEALED_HOLDOUT_NOT_HUMAN_GOLD",
    "manifest_sha256":sha(MANIFEST),
    "raw_gpu_sha256":sha(RESULTS),
    "model_id":r["model_id"],"model_revision":r["model_revision"],
    "seed":r["seed"],"gpu":r["gpu"],
    "questions":16,
    "json_object_parsed":sum(e["json_object_parsed"] for e in evaluations),
    "source_integrity_valid":sum(e["exact_source_spans_pass"] for e in evaluations),
    "developer_minimum_intents_recovered":sum(e["minimum_intents_recovered"] for e in evaluations),
    "fully_mapped_without_unresolved":sum(e["fully_mapped_without_unresolved"] for e in evaluations),
    "by_tenant_locale":by_stratum,
    "inference_generation_seconds_total":round(sum(times),3),
    "inference_generation_seconds_median":round(statistics.median(times),3),
    "model_load_seconds":r["model_load_seconds"],
    "remote_job_wall_seconds":r["wall_seconds"],
    "cuda_max_allocated_bytes":r["cuda_max_allocated_bytes"],
    "quality_decision":"RESEARCH_FEASIBILITY_NOT_PRODUCTION_RELEASE",
    "limitations":"Exact substring coverage does not certify semantic intent separation, negation preservation beyond source text, multi-intent classification correctness or policy entailment. Development labels are authored by the implementer, not independently human adjudicated.",
    "cases":evaluations
}
OUTPUT.write_text(json.dumps(summary,indent=2,ensure_ascii=False)+"\n")
print(json.dumps({
    "status":summary["status"],"manifest_sha256":summary["manifest_sha256"],
    "gpu_output_sha256":summary["raw_gpu_sha256"],"report_sha256":sha(OUTPUT),
    "json_parsed":summary["json_object_parsed"],
    "exact_source_pass":summary["source_integrity_valid"],
    "minimum_intents":summary["developer_minimum_intents_recovered"],
    "fully_mapped":summary["fully_mapped_without_unresolved"],
    "strata":summary["by_tenant_locale"],
    "model_load_seconds":summary["model_load_seconds"],
    "remote_job_wall_seconds":summary["remote_job_wall_seconds"]
},ensure_ascii=False,indent=2))
