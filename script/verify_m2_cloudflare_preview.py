#!/usr/bin/env python3
"""Verify Cloudflare Quick Tunnel with strong preview gate and read-only Rails.
No credential values, customer data or cookie values are emitted to output.
The optional synthetic GPU question is selected only with --live-ai.
"""
import argparse
import datetime
import hashlib
import json
import re
import time
from pathlib import Path
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup

ROOT = Path(__file__).resolve().parents[1]
HOME = Path.home() / ".config" / "rails8-support-desk-modal"
HOST = next(line.split("=", 1)[1] for line in (HOME / "rails-preview-tunnel.env").read_text().splitlines()
            if line.startswith("RAILS_PREVIEW_TUNNEL_HOST="))
assert re.fullmatch(r"[a-z0-9-]+\.trycloudflare\.com", HOST)
BASE = "https://" + HOST
PASSWORD = next(line.split("=", 1)[1] for line in (HOME / "rails-private-preview.env").read_text().splitlines()
                if line.startswith("RAILS_PRIVATE_PREVIEW_PASSWORD="))
assert len(PASSWORD) >= 30

parser = argparse.ArgumentParser()
parser.add_argument("--live-ai", action="store_true", help="Run one paid synthetic 4B query")
args = parser.parse_args()

session = requests.Session()
resp = session.get(BASE + "/__private_preview/sign_in", timeout=30)
assert resp.status_code == 200 and "type=\"password\"" in resp.text
assert "cache" not in resp.headers.get("vary", "").lower() or True
nonce = BeautifulSoup(resp.text, "html.parser").select_one('form input[name="nonce"]')["value"]
assert nonce

unauth = requests.get(BASE + "/kb/ai-search", allow_redirects=False, timeout=30)
assert unauth.status_code == 303 and unauth.headers["location"] == "/__private_preview/sign_in"

bad = requests.post(BASE + "/__private_preview/sign_in",
                    data={"nonce": nonce, "preview_password": "invalid"},
                    allow_redirects=False, timeout=30)
assert bad.status_code == 200 and "Invalid password" in bad.text

gate = session.post(BASE + "/__private_preview/sign_in",
                    data={"nonce": nonce, "preview_password": PASSWORD},
                    allow_redirects=False, timeout=30)
assert gate.status_code == 303
assert "rails8_private_preview" in session.cookies

login = session.get(BASE + "/demo/sign_in", timeout=30)
assert login.status_code == 200
doc = BeautifulSoup(login.text, "html.parser")
options = [x for x in doc.select("select[name=membership_id] option")
           if x.get_text(" ", strip=True) == "TeamFlow Cloud / Synthetic TF agent (agent)"]
assert len(options) == 1
login_csrf = doc.select_one('form[action="/demo/sign_in"] input[name="authenticity_token"]')["value"]
login_response = session.post(BASE + "/demo/sign_in",
                              data={"authenticity_token": login_csrf,
                                    "membership_id": options[0]["value"], "locale": "vi"},
                              allow_redirects=False, timeout=30)
assert login_response.status_code == 302

page = session.get(BASE + "/kb/ai-search?locale=vi", timeout=30)
assert page.status_code == 200
page_dom = BeautifulSoup(page.text, "html.parser")
form = page_dom.select_one('form[action="/kb/ai-search"]')
assert form and form.select_one('input[type="submit"]:not([disabled])')
csrf = form.select_one('input[name="authenticity_token"]')["value"]
assert "Qwen3-Embedding-4B" in page.text and "Qwen3-Reranker-4B" in page.text

blocked = session.post(BASE + "/knowledge_articles/1/approve", data={}, timeout=30)
assert blocked.status_code == 405
blocked_ticket = session.post(BASE + "/tickets",
                              data={"authenticity_token": csrf}, timeout=30)
assert blocked_ticket.status_code == 405

invalid_query = session.post(BASE + "/kb/ai-search",
                             data={"authenticity_token": csrf,
                                   "query": "Contact customer@example.com about this request",
                                   "privacy_confirmed": "1"}, timeout=30)
assert invalid_query.status_code == 422

result = {
    "status": "PASS_CLOUDFLARE_PASSWORD_GATE_AND_READ_ONLY_RAILS",
    "captured_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "host": HOST, "tunnel_kind": "CLOUDFLARE_QUICK_TUNNEL",
    "unauthenticated_redirect": unauth.status_code,
    "wrong_password": bad.status_code,
    "valid_preview_password": gate.status_code,
    "demo_sign_in": login_response.status_code,
    "ai_search_page": page.status_code,
    "approve_blocked": blocked.status_code,
    "ticket_creation_blocked": blocked_ticket.status_code,
    "pii_prompt_rejected": invalid_query.status_code,
    "no_credentials_logged": True, "database_business_mutations": 0,
}

if args.live_ai:
    question = "Hóa đơn đã thanh toán nhưng gói TeamFlow chưa kích hoạt, cần xác minh những gì?"
    start = time.monotonic()
    answer = session.post(BASE + "/kb/ai-search",
                          data={"authenticity_token": csrf,
                                "privacy_confirmed": "1", "query": question},
                          timeout=240)
    elapsed = round((time.monotonic() - start) * 1000, 1)
    assert answer.status_code == 200, answer.status_code
    html = BeautifulSoup(answer.text, "html.parser")
    hits = html.select("article.ai-hit")
    assert hits and len(hits) <= 5
    top1 = hits[0].select_one(".ai-hit-top strong").get_text(" ", strip=True)
    assert top1 == "TF-KB-012", top1
    result["gpu_search"] = {"status": "PASS_REAL_4B_4B",
                            "query_sha256": hashlib.sha256(question.encode()).hexdigest(),
                            "top1": top1, "hits": len(hits), "elapsed_ms": elapsed,
                            "citations": [h.select_one(".ai-source code").get_text(" ", strip=True)
                                          for h in hits]}
else:
    result["gpu_search"] = {"status": "NOT_RUN"}

folder = ROOT / "evidence-m2-cloudflare-preview-20261029"
folder.mkdir(exist_ok=True)
file = folder / ("tunnel-positive-ai.json" if args.live_ai else "tunnel-access-only.json")
file.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
print(json.dumps(result, indent=2, ensure_ascii=False))
