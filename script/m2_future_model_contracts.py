#!/usr/bin/env python3
"""Offline contracts for a POSSIBLE future decomposition + multilingual NLI pilot.
No model inference, network access, DB access or business writes.
All validations are preflight/postflight; NOT semantic fidelity validation.
"""
from __future__ import annotations
import json
import hashlib
import math
import re
from typing import Any

SCHEMA = "rails8.m2.claim_decomposition.v1"
NLI_SCHEMA = "rails8.m2.nli_candidate.v1"
TENANTS = {"teamflow-cloud", "novamart-store"}
LANGS = {"vi", "en"}
MAX_CLAIMS = 4
MAX_INPUT_CHARS = 300
PRIVATE_PATTERN = re.compile(r"https?://|www\.|[\w.+-]+@[\w.-]+\.[a-z]{2,}|(?:\+?\d[\d\s().-]{7,}\d)",re.I)

class ContractRejected(ValueError):
    pass

def check(condition: bool, message: str) -> None:
    if not condition:
        raise ContractRejected(message)

def canonical_sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()

def validate_decomposition(payload: Any, *, original_question: str, locale: str, tenant: str) -> dict:
    """Syntax/source-span guard. Does not verify LLM paraphrase faithfulness."""
    check(isinstance(payload, dict), "invalid root")
    check(set(payload) == {"schema", "tenant", "locale", "question_sha256", "claims", "unresolved"},
          "unexpected schema fields")
    check(payload["schema"] == SCHEMA, "unknown schema")
    check(isinstance(original_question,str) and original_question.isprintable() and
          12<=len(original_question)<=MAX_INPUT_CHARS and not PRIVATE_PATTERN.search(original_question),
          "input question not synthetic/valid")
    check(tenant in TENANTS and payload["tenant"] == tenant, "invalid tenant")
    check(locale in LANGS and payload["locale"] == locale, "invalid locale")
    check(payload["question_sha256"] == canonical_sha(original_question), "question hash mismatch")
    claims=payload["claims"]
    check(isinstance(claims,list) and 1<=len(claims)<=MAX_CLAIMS, "claim cardinality")
    ids=set()
    ranges=[]
    for c in claims:
        check(isinstance(c,dict) and set(c)=={
             "id","source_start","source_end","source_excerpt","hypothesis","intent","needs_case_data"},
             "claim schema fields")
        check(isinstance(c["id"],str) and re.fullmatch(r"c[1-4]",c["id"]) and
              c["id"] not in ids,"duplicate/invalid claim ID")
        ids.add(c["id"])
        start,end=c["source_start"],c["source_end"]
        check(type(start) is int and type(end) is int and
              0<=start<end<=len(original_question),"source offsets")
        check(c["source_excerpt"] == original_question[start:end],"fabricated excerpt")
        check(len(c["source_excerpt"].strip())>=8,"source excerpt too short")
        hypothesis=c["hypothesis"]
        check(isinstance(hypothesis,str) and 12<=len(hypothesis)<=800 and
              hypothesis.isprintable() and not PRIVATE_PATTERN.search(hypothesis),"invalid hypothesis")
        check(c["intent"] in {"policy_question","requested_action","case_specific_fact"},"unknown intent")
        check(type(c["needs_case_data"]) is bool,"invalid dependency")
        ranges.append((start,end))
    check(isinstance(payload["unresolved"],list) and len(payload["unresolved"])<=MAX_CLAIMS,"bad unresolved")
    for item in payload["unresolved"]:
        check(isinstance(item,dict) and set(item)=={"source_start","source_end","reason"},
              "unresolved schema fields")
        start,end=item["source_start"],item["source_end"]
        check(type(start) is int and type(end) is int and 0<=start<end<=len(original_question),
              "unresolved range")
        check(isinstance(item["reason"],str) and item["reason"] in
              {"ambiguous","too_many_intents","incomplete_context","untrusted_text"},
              "bad unresolved reason")
        ranges.append((start,end))
    # Coverage is mandatory for safety-critical original text: any unassigned
    # character containing letters or digits is a dropped intent risk.
    covered=[False]*len(original_question)
    for start,end in ranges:
        for i in range(start,end):
            covered[i]=True
    dropped="".join(ch for i,ch in enumerate(original_question)
                    if not covered[i] and ch.isalnum())
    check(not dropped, "unaccounted original text; intent may have been dropped")
    return {"valid":True,"claim_count":len(claims),"human_review_required":True,
            "unresolved_count":len(payload["unresolved"]),"schema":SCHEMA,
            "semantic_fidelity_proved":False}

def validate_nli_observation(payload: Any, *, expected_tenant: str, expected_locale: str,
                             expected_article_key: str, expected_version_id: int,
                             expected_full_body_sha256: str, approved_body: str) -> dict:
    """A source-authentic NLI measurement, not an automatic answer or decision."""
    check(isinstance(payload,dict) and set(payload)=={
          "schema","tenant","locale","article_key","article_version_id",
          "article_body_sha256","premise_excerpt","hypothesis","model_id",
          "model_revision","scores","predicted_label"},"NLI fields")
    check(payload["schema"]==NLI_SCHEMA,"NLI schema version")
    check(payload["tenant"]==expected_tenant and expected_tenant in TENANTS,"NLI tenant mismatch")
    check(payload["locale"]==expected_locale and expected_locale in LANGS,"NLI locale mismatch")
    check(payload["article_key"]==expected_article_key,"NLI article mismatch")
    check(type(payload["article_version_id"]) is int and
          payload["article_version_id"]==expected_version_id,"NLI approved version mismatch")
    check(payload["article_body_sha256"]==expected_full_body_sha256==
          canonical_sha(approved_body),"NLI approved KB body hash mismatch")
    premise=payload["premise_excerpt"]
    check(isinstance(premise,str) and 30<=len(premise)<=3500 and premise in approved_body,
          "NLI premise must be byte-exact approved KB substring")
    hypothesis=payload["hypothesis"]
    check(isinstance(hypothesis,str) and 12<=len(hypothesis)<=800 and hypothesis.isprintable(),
          "invalid NLI hypothesis")
    check(isinstance(payload["model_id"],str) and payload["model_id"].strip()
          and isinstance(payload["model_revision"],str) and
          re.fullmatch(r"[a-f0-9]{40}",payload["model_revision"]),
          "model must be pinned to full immutable revision")
    scores=payload["scores"]
    check(isinstance(scores,dict) and set(scores)=={"entailment","neutral","contradiction"},
          "require full three-way NLI scores")
    check(all(type(v) in {int,float} and math.isfinite(v) and 0<=v<=1 for v in scores.values())
          and abs(sum(scores.values())-1)<=0.005,"invalid uncalibrated score triple")
    check(payload["predicted_label"] in scores and
          scores[payload["predicted_label"]]==max(scores.values()),"invalid top label")
    return {"valid":True,"label":payload["predicted_label"],
            "scores_are_uncalibrated":True,
            "supports_autonomous_business_action":False,
            "requires_human_claim_evidence_validation":True}

if __name__=="__main__":
    print(json.dumps({"status":"OFFLINE_VALIDATOR_ONLY","decomposition_schema":SCHEMA,
      "nli_schema":NLI_SCHEMA,"model_inference":"NOT_RUN","business_writes":0}))
