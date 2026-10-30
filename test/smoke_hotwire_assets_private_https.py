#!/usr/bin/env python3
"""Authenticated HTTPS smoke of Hotwire assets and read-only Turbo Frames.

This test NEVER submits a business mutation successfully and never logs tokens.
"""
import json
import os
import pathlib
import re
import requests
from bs4 import BeautifulSoup

password = os.environ.get("RAILS_PRIVATE_PREVIEW_PASSWORD", "")
assert len(password) >= 30
hosts = re.findall(r'https://([a-z0-9-]+\.trycloudflare\.com)',
                   pathlib.Path("/tmp/rails8_m3_cloudflared.log").read_text())
assert hosts
origin = "https://" + hosts[-1]
session = requests.Session()

gate = session.get(origin + "/__private_preview/sign_in", timeout=20)
assert gate.status_code == 200
nonce = re.search(r'name="nonce"\s+value="([^"]+)"', gate.text)
assert nonce
unlocked = session.post(origin + "/__private_preview/sign_in",
    data={"nonce": nonce.group(1), "preview_password": password},
    allow_redirects=False, timeout=20)
assert unlocked.status_code == 303

signin = session.get(origin + "/demo/sign_in", timeout=20)
assert signin.status_code == 200
doc = BeautifulSoup(signin.text, "html.parser")
assert doc.select_one('form[action="/demo/sign_in"][data-turbo=false]')
owner = [x for x in doc.select('optgroup[label="TeamFlow Cloud"] option')
         if x.get_text(strip=True).startswith("Owner ·")]
assert len(owner) == 1
csrf = doc.select_one('meta[name="csrf-token"]')['content']
chosen = session.post(origin + "/demo/sign_in",
    data={"membership_id": owner[0]["value"], "locale": "en",
          "authenticity_token": csrf},
    headers={"X-CSRF-Token": csrf}, allow_redirects=False, timeout=20)
assert chosen.status_code == 303

home = session.get(origin + "/", timeout=20)
assert home.status_code == 200
html = BeautifulSoup(home.text, "html.parser")
assert html.select_one('meta[name="turbo-cache-control"][content="no-cache"]')
assert html.select_one('meta[name="turbo-prefetch"][content="false"]')
assert html.select_one('form[action="/demo/sign_out"][data-turbo=false]')
mapping = json.loads(html.select_one('script[type="importmap"]').string)["imports"]

assets = []
for specifier in ("application", "@hotwired/turbo-rails",
                  "@hotwired/stimulus", "@hotwired/stimulus-loading",
                  "controllers/submit_state_controller"):
    url = mapping.get(specifier)
    assert url and url.startswith("/assets/"), specifier
    response = session.get(origin + url, timeout=25)
    assert response.status_code == 200 and len(response.content) > 50
    assets.append({"specifier": specifier, "http": response.status_code,
                   "bytes": len(response.content)})

checks = []
for path, frame in [
    ("/tickets?status=open", "tickets_listing"),
    ("/customers?page=2", "customers_listing"),
    ("/knowledge_articles?q=refund", "kb_search_results")
]:
    response = session.get(origin + path, headers={"Turbo-Frame": frame}, timeout=25)
    assert response.status_code == 200
    dom = BeautifulSoup(response.text, "html.parser")
    rendered = dom.select_one("turbo-frame#" + frame)
    assert rendered and rendered.get("data-turbo-action") == "advance"
    # Turbo Rails intentionally omits the application layout for Turbo-Frame requests.
    assert dom.select_one("nav a[aria-current=page]") is None
    checks.append({"path": path, "frame": frame, "http": response.status_code, "partial_layout": True})

write_routes = []
for method, path in [("POST", "/tickets"), ("PATCH", "/tickets/1/status"),
                      ("POST", "/tickets/1/ticket_messages"),
                      ("POST", "/knowledge_articles/1/approve")]:
    response = session.request(method, origin + path,
        headers={"Accept": "text/vnd.turbo-stream.html"},
        allow_redirects=False, timeout=20)
    assert response.status_code == 405
    write_routes.append({"method": method, "path": path, "http": 405})

result = {
    "status": "PASS_HTTPS_HOTWIRE_ASSETS_FRAMES_AND_READONLY",
    "assets": assets, "frames": checks, "blocked_mutation_routes": write_routes,
    "turbo_drive_module_loaded_by_browser": "NOT_VERIFIED_HTTP_ONLY",
    "no_cache": True, "no_prefetch": True,
    "session_forms_no_turbo": True,
    "business_mutations": 0, "secrets_in_evidence": False
}
print(json.dumps(result, indent=2))
