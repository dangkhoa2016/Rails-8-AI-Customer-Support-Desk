#!/usr/bin/env python3
"""Live Rails HTML form → both Modal 4B services → pgvector, synthetic-only.

Uses localhost only. No browser/tunnel exposure and no actual client credentials
are read by this file. Writes only citations, article IDs and timings as evidence.
"""
import datetime
import hashlib
import json
import time
from pathlib import Path

import requests
from bs4 import BeautifulSoup

BASE = "http://127.0.0.1:3068"
CASES = [
    ("TeamFlow Cloud / Synthetic TF agent (agent)", "vi",
     "Hóa đơn đã thanh toán nhưng gói TeamFlow chưa kích hoạt, cần xác minh những gì?",
     "TF-KB-012"),
    ("NovaMart Store / Synthetic NM agent (agent)", "en",
     "Does an order of VND 499,999 qualify for free standard shipping?",
     "NM-KB-014"),
]
OUT = Path("/content/Rails-8-AI-Customer-Support-Desk/evidence-m2-rails-ui-live-20261029")
OUT.mkdir(parents=True, exist_ok=True)


def csrf(html, action=None):
    doc = BeautifulSoup(html, "html.parser")
    selector = f"form[action='{action}'] input[name='authenticity_token']" if action else "input[name='authenticity_token']"
    input_tag = doc.select_one(selector)
    if not input_tag:
        raise AssertionError("CSRF token is missing")
    return input_tag["value"]


def get_session(option, language):
    client = requests.Session()
    response = client.get(BASE + "/demo/sign_in", timeout=20)
    assert response.status_code == 200, response.status_code
    doc = BeautifulSoup(response.text, "html.parser")
    options = doc.select("select[name='membership_id'] option")
    matching = [tag for tag in options if option == tag.get_text(" ", strip=True)]
    assert len(matching) == 1, "Expected exactly one synthetic membership"
    login = client.post(
        BASE + "/demo/sign_in",
        data={"authenticity_token": csrf(response.text),
              "membership_id": matching[0]["value"], "locale": language},
        allow_redirects=False, timeout=20)
    assert login.status_code == 302 and login.headers.get("Location", "").endswith("/"), (
        login.status_code, login.headers.get("Location", ""))
    return client


def inspect_case(case_number, membership, locale, query, expected):
    client = get_session(membership, locale)
    landing = client.get(BASE + "/kb/ai-search?locale=" + locale, timeout=20)
    assert landing.status_code == 200, landing.status_code
    doc = BeautifulSoup(landing.text, "html.parser")
    assert "Qwen3-Embedding-4B" in landing.text
    assert "Qwen3-Reranker-4B" in landing.text
    assert doc.select_one("input[type='submit']:not([disabled])"), "UI search disabled"
    assert "no-store" in landing.headers.get("Cache-Control", "")
    search_form = doc.select_one("form[action='/kb/ai-search']")
    assert search_form is not None, "Search form missing"
    started = time.monotonic()
    result = client.post(
        BASE + "/kb/ai-search",
        data={"authenticity_token": csrf(landing.text, "/kb/ai-search"),
              "query": query, "privacy_confirmed": "1"},
        timeout=300)
    elapsed = round((time.monotonic() - started) * 1000, 2)
    if result.status_code != 200:
        problem = BeautifulSoup(result.text, "html.parser")
        raise AssertionError((result.status_code, [x.get_text(" ", strip=True) for x in problem.select("[role=alert],.alert")],
                              [(x.get("name"),x.get("value", "")[:20]) for x in problem.select("form input")]))
    results = BeautifulSoup(result.text, "html.parser")
    hits = results.select("article.ai-hit")
    assert 1 <= len(hits) <= 5, len(hits)
    top = hits[0].select_one(".ai-hit-top strong")
    assert top is not None
    top_article = top.get_text(" ", strip=True)
    assert top_article == expected, (top_article, expected)
    assert "no-store" in result.headers.get("Cache-Control", "")
    snippets = [h.select_one(".kb-snippet").get_text(" ", strip=True) for h in hits]
    assert all(snippets) and all(len(s) > 0 for s in snippets)
    citations = []
    for h in hits:
        evidence = h.select_one(".ai-source")
        assert evidence is not None
        text = evidence.get_text(" ", strip=True)
        assert "SHA256" in text
        assert "TF-KB-" not in text if "NovaMart" in membership else "NM-KB-" not in text
        citation = next((code.get_text(" ", strip=True) for code in h.select(".ai-source code")
                         if "#chunk-" in code.get_text()), None)
        assert citation and f"@{locale}:v2#chunk-" in citation
        citations.append(citation)
    return {"case": case_number, "tenant": "teamflow" if "TeamFlow" in membership else "novamart",
            "locale": locale, "status": "PASS_LIVE_RAILS_HTML_MODAL_4B_4B",
            "expected_article": expected, "top1": top_article,
            "hit_count": len(hits), "citation_ids": citations,
            "request_elapsed_ms": elapsed, "question_sha256": hashlib.sha256(query.encode()).hexdigest()}


results = []
for idx, args in enumerate(CASES, 1):
    result = inspect_case(idx, *args)
    results.append(result)
    print("CASE", result["case"], result["tenant"], result["locale"],
          "TOP1", result["top1"], "HITS", result["hit_count"],
          "LATENCY_MS", result["request_elapsed_ms"], flush=True)

summary = {"status": "PASS_LIVE_RAILS_UI_VI_EN", "captured_utc": datetime.datetime.now(
    datetime.timezone.utc).isoformat(), "origin": "http://127.0.0.1:3068",
           "mode": "LOCAL_ONLY_SYNTHETIC_TEST", "model": [
               "Qwen/Qwen3-Embedding-4B", "Qwen/Qwen3-Reranker-4B"],
           "cases": results, "real_model_calls": 4, "database_writes": "NONE_BUSINESS",
           "public_tunnel": "NOT_OPENED"}
(OUT / "rails-ui-live-results.json").write_text(json.dumps(summary, indent=2) + "\n")
print("FINAL_RESULT", json.dumps({k: v for k, v in summary.items() if k != "cases"}))
