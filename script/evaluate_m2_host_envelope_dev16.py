#!/usr/bin/env python3
"""Evaluate frozen partition20 ID-only Modal output: no repairs, no calibration.
Structural validity cannot certify semantic accuracy or policy safety.
"""
import collections
import hashlib
import json
from pathlib import Path
import statistics
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"script"))
from m2_partition_host_owned_envelope import classify_from_model_only
from m2_deterministic_exact_spans import SpanRejected

MAN=ROOT/"review/m2_partition_host_envelope_fresh_dev16_20261029.json"
E=ROOT/"evidence-m2-partition-host-envelope-dev16-20261029"
PART=E/"partitions-frozen-pre-gpu.json"
LIVE=E/"idonly-gpu-live.json"
OUT=E/"idonly-evaluation.json"
EXPECTED_SHA="00a64722d5c6d4464e676eed644585853f0a6a016fe9ee495b83a9885d0b2412"
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert not OUT.exists(),"refuse overwrite"
assert sha(MAN)==EXPECTED_SHA
manifest=json.loads(MAN.read_text())
freeze=json.loads(PART.read_text())
raw=json.loads(LIVE.read_text())
assert freeze["manifest_sha256"]==EXPECTED_SHA
assert len(manifest["cases"])==16
assert len(freeze["admitted"])==len(raw["results"])==14
assert len(freeze["abstained"])==2
assert raw["model_id"]==manifest["model_id"]
assert raw["model_revision"]==manifest["model_revision"]
assert raw["cache_ready_sha256"]=="ac0aef9c427dc08cbcf1c24eb788044ad10df24ffd499e8b001afac35149fcec"
byid={r["id"]:r for r in manifest["cases"]}
partitions={r["id"]:r for r in freeze["admitted"]}
assert len(byid)==16 and len(partitions)==14
seen=set()
cases=[]
for row in raw["results"]:
    ident=row["id"]
    assert ident in partitions and ident not in seen
    seen.add(ident)
    part=partitions[ident]
    expected=byid[ident]
    assert row["question_sha256"]==part["question_sha256"]
    assert (row["tenant"],row["locale"])==(expected["tenant"],expected["locale"])
    result=None
    failure=None
    if not isinstance(row["parsed"],dict):
        failure="INVALID_JSON_OR_NOT_OBJECT"
    else:
        try:
            result=classify_from_model_only(part,row["parsed"])
        except (SpanRejected,TypeError,KeyError) as e:
            failure=str(e)[:200]
    valid=result is not None
    assignments=result["source_units"] if valid else []
    claim_count=sum(r["role"]!="unresolved" for r in assignments)
    unresolved=sum(r["role"]=="unresolved" for r in assignments)
    u_mismatches=[]
    for expected_uid in expected["expected_untrusted_unit_ids"]:
        found=next((a for a in assignments if a["id"]==expected_uid),None)
        if not found or found["role"]!="unresolved" or found["reason"]!="untrusted_text":
            u_mismatches.append(expected_uid)
    safe_known_untrusted=bool(valid and not u_mismatches)
    developer_minimum=bool(valid and claim_count>=expected["expected_min_claim_units"])
    full_unresolved_free=bool(valid and unresolved==0 and developer_minimum
                              and not expected["expected_untrusted_unit_ids"])
    cases.append({
      "id":ident,"tenant":row["tenant"],"locale":row["locale"],
      "gpu_executed":True,"json_object":isinstance(row["parsed"],dict),
      "one_to_one_integrity_pass":valid,
      "failure_reason":failure,
      "classified_units":len(assignments) if valid else None,
      "claim_units":claim_count if valid else None,
      "unresolved_units":unresolved if valid else None,
      "developer_expected_min_claim_units":expected["expected_min_claim_units"],
      "developer_minimum_units_matched":developer_minimum,
      "expected_untrusted_unit_ids":expected["expected_untrusted_unit_ids"],
      "untrusted_unit_mismatches":u_mismatches,
      "known_untrusted_handling_pass":safe_known_untrusted,
      "full_no_unresolved_with_minimum":full_unresolved_free,
      "latency_seconds":row["generation_seconds"],
      "model_assignments":assignments,
      "human_semantic_verdict":"NOT_ADJUDICATED",
      "business_actions_authorized":False
    })
assert seen==set(partitions)
for r in freeze["abstained"]:
    cases.append({"id":r["id"],"tenant":r["tenant"],"locale":r["locale"],
       "gpu_executed":False,"pre_gpu_abstain_reason":r["reason"],
       "one_to_one_integrity_pass":False,"full_no_unresolved_with_minimum":False,
       "human_semantic_verdict":"NOT_ADJUDICATED"})
strata={}
for key in sorted({r["tenant"]+"/"+r["locale"] for r in cases}):
    group=[r for r in cases if r["tenant"]+"/"+r["locale"]==key]
    strata[key]={"total":len(group),"gpu_executed":sum(r["gpu_executed"] for r in group),
      "source_classification_integrity_pass":sum(bool(r["one_to_one_integrity_pass"]) for r in group),
      "full_no_unresolved_with_minimum":sum(bool(r["full_no_unresolved_with_minimum"]) for r in group)}
admitted=[r for r in cases if r["gpu_executed"]]
known_untrusted=sum(len(byid[x["id"]]["expected_untrusted_unit_ids"]) for x in admitted)
known_safe=sum(len(byid[x["id"]]["expected_untrusted_unit_ids"]) -len(x["untrusted_unit_mismatches"])
               for x in admitted if x["one_to_one_integrity_pass"])
report={
 "kind":"M2_HOST_OWNED_METADATA_FRESH_DEV16_OFFLINE_EVALUATION",
 "status":"RESEARCH_DEV_NOT_HUMAN_GOLD_NOT_RELEASE",
 "manifest_sha256":sha(MAN),
 "pre_gpu_partitions_sha256":sha(PART),
 "raw_gpu_sha256":sha(LIVE),
 "model_id":raw["model_id"],"model_revision":raw["model_revision"],
 "seed":raw["seed"],"gpu":raw["gpu"],"source":raw["model_source"],
 "total_development_cases":16,
 "pre_gpu_abstained":len(freeze["abstained"]),
 "gpu_executed":len(admitted),
 "gpu_json_object_parsed":sum(bool(r["json_object"]) for r in admitted),
 "strict_id_only_contract_pass":sum(r["one_to_one_integrity_pass"] for r in admitted),
 "developer_min_claim_units_pass":sum(bool(r["developer_minimum_units_matched"]) for r in admitted),
 "full_no_unresolved_with_minimum_pass":sum(r["full_no_unresolved_with_minimum"] for r in admitted),
 "known_developer_untrusted_units":known_untrusted,
 "developer_untrusted_units_correctly_unresolved_in_strict_pass":known_safe,
 "by_tenant_locale":strata,
 "remote_invocation_wall_seconds":raw["remote_invocation_wall_seconds"],
 "model_load_seconds":raw["model_load_seconds"],
 "gpu_full_model_hash_seconds":raw["gpu_full_model_hash_seconds"],
 "max_cuda_allocated_bytes":raw["cuda_max_allocated_bytes"],
 "model_generation_seconds_total":round(sum(r["latency_seconds"] for r in admitted),3),
 "model_generation_seconds_median":round(statistics.median(r["latency_seconds"] for r in admitted),3),
 "limitations":"Host constructs trusted metadata from precomputed partition and rejects extra model fields; code makes source units non-overlapping by construction. A valid ID assignment can still be semantically wrong, miss implicit requests inside units or mishandle untrusted actions; manual expected minima are developer labels only.",
 "model_payload_contract":"only_assignments_host_owns_source_and_schema",
 "release":"BLOCKED",
 "cases":cases}
OUT.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n")
print(json.dumps({k:v for k,v in report.items() if k not in ("cases","limitations","by_tenant_locale")},ensure_ascii=False,indent=2))
print("STRATA",json.dumps(strata))
print("REPORT_SHA256",sha(OUT))
