"""M2 partition-aware SOURCE-LOCKED units and strict one-to-one classification.
Research only; not a semantic verifier, not an action authorization.
External model cannot create, replace, delete or reposition source spans.
"""
import hashlib
import re

from m2_deterministic_exact_spans import PRIVATE_PATTERN, SpanRejected

SPLITS = re.compile(r";(?=\s|$)|[?!](?=\s|$)|,(?=\s+(?:và|and)\b)", re.I)
ROLE = {"policy_question", "requested_action", "case_specific_fact", "unresolved"}
REASON = {"ambiguous", "too_many_intents", "incomplete_context", "untrusted_text"}
MAX_UNITS = 4

def ensure(ok, reason):
    if not ok: raise SpanRejected(reason)

def source_units(question, *, tenant, locale):
    ensure(isinstance(question,str) and question.isprintable() and
           15 <= len(question) <= 420,"invalid_question")
    ensure(tenant in {"teamflow-cloud","novamart-store"} and
           locale in {"vi","en"},"invalid_tenant_locale")
    ensure(not PRIVATE_PATTERN.search(question),"potential_private_content")
    segments=[]
    start=0
    for match in SPLITS.finditer(question):
        end=match.end()
        if end>start:
            segments.append((start,end))
            start=end
    if start<len(question):segments.append((start,len(question)))
    ensure(2<=len(segments)<=MAX_UNITS,"partition_not_reliable_2_to_4_units")
    units=[]
    for i,(start,end) in enumerate(segments,1):
        chunk=question[start:end]
        ensure(len(chunk.strip())>=9 and any(c.isalnum() for c in chunk),
               "degenerate_source_unit")
        units.append({"id":f"u{i}","source_start":start,"source_end":end,
                      "source_excerpt":chunk})
    ensure("".join(u["source_excerpt"] for u in units)==question,
           "lossless_reconstruction_failed")
    ensure(units[0]["source_start"]==0 and
           units[-1]["source_end"]==len(question),"partition_drift")
    return {"schema":"rails8.m2.source_partition.v1",
       "tenant":tenant,"locale":locale,
       "question_sha256":hashlib.sha256(question.encode("utf-8")).hexdigest(),
       "unit_count":len(units),"units":units,
       "boundary_policy":"punctuation_conservative_no_model_offsets",
       "semantics_verified":False}

def validate_assignments(partition, output):
    ensure(isinstance(output,dict) and
           set(output)=={"schema","question_sha256","assignments"},
           "unexpected_classifier_schema")
    ensure(output["schema"]=="rails8.m2.partition_labels.v1",
           "classifier_schema_mismatch")
    ensure(output["question_sha256"]==partition["question_sha256"],
           "question_hash_mismatch")
    rows=output["assignments"]
    units=partition["units"]
    ensure(isinstance(rows,list) and len(rows)==len(units),
           "missing_or_extra_unit_assignments")
    resolved=[]
    for u,a in zip(units,rows):
        ensure(isinstance(a,dict) and
               set(a)=={"unit_id","role","needs_case_data","reason"},
               "unexpected_assignment_keys")
        ensure(a["unit_id"]==u["id"],"reordered_duplicate_or_missing_unit")
        ensure(a["role"] in ROLE,"invalid_classification")
        ensure(type(a["needs_case_data"]) is bool,"invalid_case_dependency")
        reason=a["reason"]
        if a["role"]=="unresolved":
            ensure(reason in REASON,"unresolved_requires_reason")
        else:
            ensure(reason is None,"non_unresolved_reason_not_null")
        resolved.append({**u,"role":a["role"],
                         "needs_case_data":a["needs_case_data"],
                         "reason":reason})
    return {"schema":"rails8.m2.partition_classification.v1",
      "tenant":partition["tenant"],"locale":partition["locale"],
      "question_sha256":partition["question_sha256"],
      "source_units":resolved,
      "source_integrity_verified":True,
      "all_units_exclusively_classified":True,
      "semantic_fidelity_verified":False,
      "human_review_required":True,
      "business_actions_authorized":False,
      "customer_answer_permitted":False}
