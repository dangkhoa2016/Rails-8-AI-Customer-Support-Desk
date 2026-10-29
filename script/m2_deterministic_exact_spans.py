"""Deterministic, fail-closed source-span recovery for manually/research-generated
EXACT query excerpts. This DOES NOT assess intent semantics or policy entailment.
No normalization, fuzzy matching, model-written character offsets or KB writes.
"""
from __future__ import annotations
import hashlib
import re
from typing import Any

MAX_CLAIMS = 4
MAX_UNRESOLVED = 4
ALLOWED_INTENTS = {"policy_question", "requested_action", "case_specific_fact"}
ALLOWED_REASONS = {"ambiguous", "too_many_intents", "incomplete_context", "untrusted_text"}
ALLOWED_TENANTS = {"teamflow-cloud", "novamart-store"}
ALLOWED_LOCALES = {"vi", "en"}
PRIVATE_PATTERN = re.compile(
    r"https?://|www\.|[\w.+-]+@[\w.-]+\.[a-z]{2,}|(?:\+?\d[\d\s().-]{7,}\d)", re.I
)

class SpanRejected(ValueError):
    pass

def insist(ok: bool, why: str) -> None:
    if not ok:
        raise SpanRejected(why)

def resolve_unique(query: str, excerpt: str) -> tuple[int,int]:
    insist(isinstance(excerpt, str) and excerpt == excerpt.strip()
           and 8 <= len(excerpt) <= len(query), "invalid excerpt length/boundaries")
    first = query.find(excerpt)
    insist(first >= 0, "nonverbatim excerpt")
    insist(query.find(excerpt, first + 1) < 0, "ambiguous repeated excerpt")
    return first, first + len(excerpt)

def recover(query: str, model_output: Any, *, tenant: str, locale: str) -> dict:
    insist(isinstance(query, str) and query.isprintable()
           and 12 <= len(query) <= 400, "invalid source question")
    insist(not PRIVATE_PATTERN.search(query), "potentially private input")
    insist(tenant in ALLOWED_TENANTS and locale in ALLOWED_LOCALES, "invalid tenant/locale")
    insist(isinstance(model_output, dict) and
           set(model_output) == {"claims", "unresolved"}, "unexpected output shape")
    claims = model_output["claims"]
    unresolved = model_output["unresolved"]
    insist(isinstance(claims, list) and 1 <= len(claims) <= MAX_CLAIMS,
           "invalid claim cardinality")
    insist(isinstance(unresolved, list) and len(unresolved) <= MAX_UNRESOLVED,
           "invalid unresolved cardinality")
    occupied = [None]*len(query)
    claims_resolved = []
    unresolved_resolved = []
    ids = set()
    for position, entry in enumerate(claims):
        insist(isinstance(entry, dict) and set(entry)=={
            "id", "excerpt", "intent", "needs_case_data"}, "invalid claim keys")
        expected = f"c{position+1}"
        insist(entry["id"] == expected and entry["id"] not in ids, "invalid/duplicate claim ID")
        ids.add(expected)
        insist(entry["intent"] in ALLOWED_INTENTS, "invalid intent value")
        insist(type(entry["needs_case_data"]) is bool, "invalid dependency value")
        start,end=resolve_unique(query, entry["excerpt"])
        for i in range(start,end):
            insist(occupied[i] is None,"overlapping selected spans")
            occupied[i]=entry["id"]
        claims_resolved.append({
            "id":entry["id"], "source_start":start,"source_end":end,
            "source_excerpt":entry["excerpt"], "intent":entry["intent"],
            "needs_case_data":entry["needs_case_data"]
        })
    for ix, entry in enumerate(unresolved,1):
        insist(isinstance(entry, dict) and set(entry)=={"excerpt","reason"},
               "invalid unresolved keys")
        insist(entry["reason"] in ALLOWED_REASONS, "invalid unresolved reason")
        start,end=resolve_unique(query,entry["excerpt"])
        ident=f"u{ix}"
        for i in range(start,end):
            insist(occupied[i] is None,"overlap with existing span")
            occupied[i]=ident
        unresolved_resolved.append({
            "source_start":start,"source_end":end,
            "source_excerpt":entry["excerpt"],"reason":entry["reason"]
        })
    dropped=[i for i,ch in enumerate(query) if ch.isalnum() and occupied[i] is None]
    insist(not dropped, "dropped query content (intent coverage failure)")
    ordered=sorted((x["source_start"],x["source_end"]) for x in
                   [*claims_resolved,*unresolved_resolved])
    insist(all(ordered[i][1] <= ordered[i+1][0] for i in range(len(ordered)-1)),
           "overlapping source order")
    return {
        "schema":"rails8.m2.deterministic_exact_span.v1",
        "question_sha256":hashlib.sha256(query.encode("utf-8")).hexdigest(),
        "tenant":tenant,"locale":locale,
        "claims":claims_resolved,"unresolved":unresolved_resolved,
        "claim_count":len(claims_resolved),
        "unresolved_count":len(unresolved_resolved),
        "all_alphanumeric_source_covered":True,
        "source_integrity_verified":True,
        "semantic_fidelity_verified":False,
        "business_actions_authorized":False,
        "human_review_required":True
    }
