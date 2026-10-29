#!/usr/bin/env python3
"""LOCAL_ONLY. Test protected Colab preview form and Rails AI Search without GPU calls."""
import datetime
import json
from pathlib import Path
import requests
from bs4 import BeautifulSoup

BASE = "http://127.0.0.1:3068"
KEYFILE = Path.home() / ".config/rails8-support-desk-modal/rails-private-preview.env"
PASSWORD = next(l.partition("=")[2] for l in KEYFILE.read_text().splitlines()
                if l.startswith("RAILS_PRIVATE_PREVIEW_PASSWORD="))
assert len(PASSWORD) >= 30

def field(html, selector):
    found = BeautifulSoup(html, "html.parser").select_one(selector)
    assert found is not None and found.get("value")
    return found["value"]

def check_user(tenant, label, lang):
    client = requests.Session()
    redirect = client.get(BASE + "/demo/sign_in", allow_redirects=False, timeout=10)
    assert redirect.status_code == 303 and redirect.headers["location"] == "/__private_preview/sign_in"
    login = client.get(BASE + "/__private_preview/sign_in", timeout=10)
    assert login.status_code == 200 and "Private Colab preview" in login.text
    assert "frame-ancestors" in login.headers.get("Content-Security-Policy", "")
    nonce = field(login.text, 'form[action="/__private_preview/sign_in"] input[name="nonce"]')
    unlocked = client.post(BASE + "/__private_preview/sign_in", allow_redirects=False,
        data={"nonce": nonce, "preview_password": PASSWORD}, timeout=10)
    assert unlocked.status_code == 303 and "rails8_private_preview" in client.cookies
    signin = client.get(BASE + "/demo/sign_in", timeout=10)
    assert signin.status_code == 200 and "membership_id" in signin.text
    doc = BeautifulSoup(signin.text, "html.parser")
    options = [o for o in doc.select("select[name=membership_id] option")
               if o.get_text(" ", strip=True) == label]
    assert len(options) == 1
    auth = client.post(BASE + "/demo/sign_in", allow_redirects=False, timeout=10,
        data={"authenticity_token": field(signin.text, 'form[action="/demo/sign_in"] input[name="authenticity_token"]'),
              "membership_id": options[0]["value"], "locale": lang})
    assert auth.status_code == 302, auth.status_code
    search = client.get(BASE + "/kb/ai-search?locale=" + lang, timeout=10)
    assert search.status_code == 200
    form = BeautifulSoup(search.text, "html.parser").select_one("form[action='/kb/ai-search']")
    assert form is not None
    assert form.select_one('input[type=submit]:not([disabled])') is not None
    assert search.headers.get('Content-Security-Policy', '').startswith('frame-ancestors ')
    assert not search.headers.get('X-Frame-Options')
    assert 'no-store' in search.headers.get('Cache-Control', '')
    denied = client.post(BASE + "/kb/ai-search", timeout=10,
        data={"authenticity_token": field(search.text, 'form[action="/kb/ai-search"] input[name="authenticity_token"]'),
              "privacy_confirmed": "1", "query": "Send customer@example.com an email to review the order"})
    assert denied.status_code == 422, denied.status_code
    return {"tenant": tenant, "locale": lang, "preview_redirect": redirect.status_code,
            "private_preview_login": login.status_code, "private_password_submit": unlocked.status_code,
            "demo_login": auth.status_code, "AI_search_page": search.status_code,
            "PII_rejected": denied.status_code, "model_calls": 0}

results = [
    check_user("TeamFlow", "TeamFlow Cloud / Synthetic TF agent (agent)", "vi"),
    check_user("NovaMart", "NovaMart Store / Synthetic NM agent (agent)", "en")
]
report = {"status": "PASS_LOCAL_PASSWORD_FORM_GATE_RAILS_UI", "utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
          "results": results, "rails_loopback_only": True,
          "public_colab_browser": "NOT_VERIFIED_BY_BROWSER", "model_calls": 0}
out = Path("/content/Rails-8-AI-Customer-Support-Desk/evidence-m2-rails-colab-iframe-20261029")
out.mkdir(exist_ok=True)
(out / "form-gate-acceptance.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
