#!/usr/bin/env python3
"""Read-only Rails M3 smoke through the local password-form gate; no secret output."""
import json
import os
import pathlib
import re
from urllib.parse import urljoin
import requests

PASSWORD = os.environ.get("RAILS_PRIVATE_PREVIEW_PASSWORD", "")
assert len(PASSWORD) >= 30, "Private password must be supplied privately"
PUBLIC = os.environ.get("M3_SMOKE_TUNNEL") == "YES"
BASE = "http://127.0.0.1:3068"
if PUBLIC:
    # Never transmit the protected preview password to a caller-selected host.
    log = pathlib.Path("/tmp/rails8_m3_cloudflared.log").read_text()
    hosts = re.findall(r"https://([a-z0-9-]+\.trycloudflare\.com)", log)
    assert hosts, "No exact active M3 tunnel hostname"
    BASE = "https://" + hosts[-1]

def csrf(html):
    match = re.search(r'<meta\s+name="csrf-token"\s+content="([^"]+)"', html)
    assert match, "Missing Rails CSRF token"
    return match.group(1)

def signin(want):
    session = requests.Session()
    response = session.get(BASE + "/__private_preview/sign_in", timeout=15)
    assert response.status_code == 200 and 'type="password"' in response.text
    nonce = re.search(r'name="nonce"\s+value="([^"]+)"', response.text)
    assert nonce
    response = session.post(BASE + "/__private_preview/sign_in",
        data={"nonce": nonce.group(1), "preview_password": PASSWORD},
        allow_redirects=False, timeout=15)
    assert response.status_code == 303, f"Preview auth status: {response.status_code}"
    login = session.get(BASE + "/demo/sign_in", timeout=15)
    assert login.status_code == 200
    options = re.findall(r'<option\s+value="(\d+)"[^>]*>(.*?)</option>', login.text, re.S)
    matches = [value for value, label in options if want in label]
    assert len(matches) == 1, f"Unable to locate unique synthetic {want} membership"
    response = session.post(BASE + "/demo/sign_in",
        data={"membership_id": matches[0], "locale": "vi", "authenticity_token": csrf(login.text)},
        headers={"X-CSRF-Token": csrf(login.text)},
        allow_redirects=False, timeout=15)
    assert response.status_code in (302, 303), f"Demo sign-in failed: {response.status_code}"
    return session

def inspect(tenant, account, own_prefix, other_prefix):
    session = signin(account)
    index = session.get(BASE + "/tickets", timeout=20)
    assert index.status_code == 200 and own_prefix in index.text
    assert other_prefix not in index.text, "Cross-tenant ticket leak"
    assert "Synthetic" in index.text or "synthetic" in index.text or "giả lập" in index.text

    filtered = session.get(BASE + "/tickets", params={"status":"open","customer_locale":"vi"}, timeout=20)
    assert filtered.status_code == 200
    urls = re.findall(r'href="(/tickets/\d+)"', filtered.text)
    assert len(urls) == 10, f"Expected 10 VI/open ticket links, got {len(urls)}"
    assert other_prefix not in filtered.text

    detail = session.get(urljoin(BASE, urls[0]), timeout=20)
    assert detail.status_code == 200
    assert "business" in detail.text.lower() or "nghiệp vụ" in detail.text.lower()
    assert other_prefix not in detail.text
    ai = session.get(BASE + "/kb/ai-search", timeout=20)
    assert ai.status_code == 200
    return {"tenant":tenant,"ticket_index_status":index.status_code,
            "open_vi_filter_tickets":len(urls),"detail_status":detail.status_code,
            "ai_search_page_status":ai.status_code,"cross_tenant_leak":False}

def run():
    session = requests.Session()
    gate = session.get(BASE + "/tickets", allow_redirects=False, timeout=15)
    assert gate.status_code == 303
    results = [
        inspect("teamflow-cloud","Synthetic TF agent","TF-M3-","NM-M3-"),
        inspect("novamart-store","Synthetic NM agent","NM-M3-","TF-M3-"),
    ]
    print(json.dumps({"status":"PASS_PUBLIC_RAILS_M3_READONLY_HTTP" if PUBLIC else "PASS_LOCAL_RAILS_M3_HTTP","gate_without_auth":303, "origin_type":"ephemeral_https_quick_tunnel" if PUBLIC else "loopback",
                      "results":results,"post_requests_other_than_login":"NONE",
                      "credentials_recorded":False},indent=2))
if __name__ == "__main__":
    run()
