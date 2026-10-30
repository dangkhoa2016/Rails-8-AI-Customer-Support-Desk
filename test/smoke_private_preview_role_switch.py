#!/usr/bin/env python3
"""Private read-only tunnel: login and logout (session state only, no business writes).

Never log the preview password, tokens, cookies, or HTML form contents.
"""
import json
import os
import pathlib
import re
import requests
from urllib.parse import urlparse
from bs4 import BeautifulSoup

password = os.environ.get("RAILS_PRIVATE_PREVIEW_PASSWORD", "")
assert len(password) >= 30
public = os.environ.get("M3_SMOKE_TUNNEL") == "YES"
origin = "http://127.0.0.1:3068"
if public:
    hosts = re.findall(r"https://([a-z0-9-]+\.trycloudflare\.com)",
                       pathlib.Path("/tmp/rails8_m3_cloudflared.log").read_text())
    assert hosts
    origin = "https://" + hosts[-1]
session = requests.Session()
gate = session.get(origin + "/__private_preview/sign_in", timeout=20)
assert gate.status_code == 200
nonce = re.search(r'name="nonce"\s+value="([^"]+)"', gate.text)
assert nonce
authenticated = session.post(origin + "/__private_preview/sign_in",
    data={"nonce": nonce.group(1), "preview_password": password},
    allow_redirects=False, timeout=20)
assert authenticated.status_code == 303
login = session.get(origin + "/demo/sign_in", timeout=20)
assert login.status_code == 200
soup = BeautifulSoup(login.text, "html.parser")
option = soup.select_one('optgroup[label="TeamFlow Cloud"] option')
assert option
csrf = soup.select_one('meta[name="csrf-token"]')["content"]
selected = session.post(origin + "/demo/sign_in",
    data={"membership_id": option["value"], "locale": "vi", "authenticity_token": csrf},
    headers={"X-CSRF-Token": csrf}, allow_redirects=False, timeout=20)
assert selected.status_code in (302, 303)
dashboard = session.get(origin + "/", timeout=20)
assert dashboard.status_code == 200 and "TeamFlow Cloud" in dashboard.text
dash = BeautifulSoup(dashboard.text, "html.parser")
logout = dash.select_one('form[action="/demo/sign_out"]')
assert logout is not None and logout.get("method", "").lower() == "post"
payload = {control.get("name"): control.get("value") for control in logout.select("input[name]")}
assert payload.get("_method") == "delete" and payload.get("authenticity_token")
response = session.post(origin + "/demo/sign_out", data=payload,
    allow_redirects=False, timeout=20)
logout_path = urlparse(response.headers.get("Location", "")).path
assert response.status_code in (302, 303), "role switch logout is blocked"
assert logout_path == "/demo/sign_in", "signout redirect mismatch"

switched = session.get(origin + "/demo/sign_in", timeout=20)
assert switched.status_code == 200
switch_doc = BeautifulSoup(switched.text, "html.parser")
owner_choices = [
    o for o in switch_doc.select('optgroup[label="NovaMart Store"] option')
    if o.get_text(strip=True).startswith("Owner ·")
]
assert len(owner_choices) == 1
next_csrf = switch_doc.select_one('meta[name="csrf-token"]')["content"]
new_role = session.post(origin + "/demo/sign_in",
    data={"membership_id": owner_choices[0]["value"], "locale":"en",
          "authenticity_token": next_csrf},
    headers={"X-CSRF-Token":next_csrf},
    allow_redirects=False, timeout=20)
assert new_role.status_code in (302, 303)
new_dashboard = session.get(origin + "/", timeout=20)
assert new_dashboard.status_code == 200
nav = BeautifulSoup(new_dashboard.text, "html.parser").select_one("nav").get_text(" ", strip=True)
assert "NovaMart Store · owner" in nav and "TeamFlow Cloud" not in nav

print(json.dumps({"status":"PASS_PRIVATE_ROLE_SWITCH_END_TO_END",
    "origin_type": "private_cloudflare_https" if public else "loopback",
    "initial_role":"teamflow-cloud/viewer",
    "final_role":"novamart-store/owner",
    "logout_real_http_method":"POST","logout_rails_method_override":"delete",
    "logout_status":response.status_code,"logout_redirect_path":logout_path,
    "new_role_login_status":new_role.status_code,
    "final_dashboard_status":new_dashboard.status_code,
    "cross_tenant_nav_leak":False,"business_mutations":0,"tokens_logged":False}))
