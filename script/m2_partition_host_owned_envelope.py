"""Predeclared protocol: model owns ONLY assignments; host owns trusted envelope.
This is NOT repair of old 20-case GPU output, and no semantic accuracy claim.
"""
import hashlib
import json
from m2_deterministic_exact_spans import SpanRejected
from m2_partition_aware_units import validate_assignments

def classify_from_model_only(partition, model_payload):
    if not isinstance(model_payload,dict) or set(model_payload)!={"assignments"}:
        raise SpanRejected("raw_model_payload_must_contain_only_assignments")
    # The model is never asked to echo, create or rewrite a source hash/schema.
    # The host injects ONLY authoritative data from its precomputed partition.
    envelope={
        "schema":"rails8.m2.partition_labels.v1",
        "question_sha256":partition["question_sha256"],
        "assignments":model_payload["assignments"]
    }
    result=validate_assignments(partition,envelope)
    result["trusted_metadata_origin"]="host_precomputed_source_partition"
    result["model_supplied_source_metadata"]=False
    result["raw_model_payload_sha256"]=hashlib.sha256(
        json.dumps(model_payload,ensure_ascii=False,sort_keys=True,
                   separators=(",",":")).encode("utf-8")).hexdigest()
    return result
