#!/usr/bin/env python3
"""HTTPS/local read-only smoke for grouped demo accounts and role explanations.

No tokens, passwords or cookies are persisted or printed. Public HTTPS origin is
resolved only from the running project's Cloudflare Quick Tunnel log.
"""
import json
import os
import pathlib
import re
import requests
from bs4 import BeautifulSoup

PASSWORD = os.environ.get("RAILS_PRIVATE_PREVIEW_PASSWORD", "")
assert len(PASSWORD) >= 30, "Private preview password must be supplied privately"
PUBLIC = os.environ.get("M3_SMOKE_TUNNEL") == "YES"
ORIGIN = "http://127.0.0.1:3068"
if PUBLIC:
    log = pathlib.Path("/tmp/rails8_m3_cloudflared.log").read_text()
    known = re.findall(r"https://([a-z0-9-]+\.trycloudflare\.com)", log)
    assert known, "Missing exact tunnel origin"
    ORIGIN = "https://" + known[-1]


def check_page(session, locale):
    response = session.get(ORIGIN + "/demo/sign_in", params={"locale": locale}, timeout=18)
    assert response.status_code == 200, ("sign-in view", response.status_code)
    soup = BeautifulSoup(response.text, "html.parser")
    assert soup.html.get("lang") == locale
    assert not soup.find(string=re.compile("Translation missing", re.I))
    selector = soup.select_one('select[name="membership_id"][aria-describedby="demo-role-help"]')
    assert selector
    groups = selector.find_all("optgroup")
    assert len(groups) == 2 and {x["label"] for x in groups} == {"TeamFlow Cloud", "NovaMart Store"}
    assert all(len(group.find_all("option")) == 3 for group in groups)
    assert len(selector.find_all("option")) == 6
    assert len(soup.select("article.demo-role-card")) == 3
    assert len(soup.select("ol.demo-test-steps li")) == 3
    text = soup.get_text(" ", strip=True)
    for role in ("Viewer", "Agent", "Owner"):
        assert role in text, role
    if locale == "vi":
        assert "Ba vai trò dùng để thử nghiệm" in text
        assert "Hướng dẫn thử demo" in text
        assert "Chú ý bảo mật" in text
        assert "Cloudflare Private Demo" in text
        assert "Answerability" in text
    else:
        assert "Three roles to explore" in text
        assert "How to explore this demo" in text
        assert "blocked over the tunnel" in text
        assert "Answerability remains blocked" in text
    return soup


def authenticate_gate():
    session = requests.Session()
    landing = session.get(ORIGIN + "/__private_preview/sign_in", timeout=18)
    assert landing.status_code == 200
    nonce = re.search(r'name="nonce"\s+value="([^"]+)"', landing.text)
    assert nonce
    response = session.post(ORIGIN + "/__private_preview/sign_in",
        data={"nonce": nonce.group(1), "preview_password": PASSWORD},
        allow_redirects=False, timeout=18)
    assert response.status_code == 303
    return session


def check_role(session, organization, role):
    login = check_page(session, "en")
    groups = {g.get("label"): g for g in login.select("optgroup")}
    options = [o for o in groups[organization].select("option")
               if o.get_text(strip=True).startswith(role.title() + " ·")]
    assert len(options) == 1, (organization, role)
    token = login.select_one('meta[name="csrf-token"]')["content"]
    result = session.post(ORIGIN + "/demo/sign_in",
        data={"membership_id": options[0]["value"], "locale": "en",
              "authenticity_token": token},
        headers={"X-CSRF-Token": token}, allow_redirects=False, timeout=18)
    assert result.status_code in (302, 303)
    index = session.get(ORIGIN + "/tickets", timeout=18)
    assert index.status_code == 200
    expected, forbidden = ("TF-M3-", "NM-M3-") if organization == "TeamFlow Cloud" else ("NM-M3-", "TF-M3-")
    assert expected in index.text and forbidden not in index.text
    index_soup = BeautifulSoup(index.text, "html.parser")
    assert f"{organization} · {role}" in index_soup.select_one("nav").get_text(" ", strip=True)
    new_ticket = bool(index_soup.select('a[href="/tickets/new"]'))
    ai_navigation = bool(index_soup.select('nav a[href="/kb/ai-search"]'))
    assert new_ticket == (role != "viewer")
    assert ai_navigation == (role != "viewer")
    knowledge = session.get(ORIGIN + "/knowledge_articles", timeout=18)
    assert knowledge.status_code == 200
    compare_links = bool(BeautifulSoup(knowledge.text, "html.parser").select('a[href*="/compare"]'))
    assert compare_links == (role == "owner")
    return {"organization": organization, "role": role,
            "tickets_http": index.status_code, "knowledge_http": knowledge.status_code,
            "new_ticket_control": new_ticket, "ai_search_nav": ai_navigation,
            "kb_compare_control": compare_links, "cross_tenant_leak": False}


def main():
    unknown = requests.get(ORIGIN + "/demo/sign_in", allow_redirects=False, timeout=18)
    assert unknown.status_code == 303
    main_session = authenticate_gate()
    for locale in ("vi", "en"):
        check_page(main_session, locale)
    checks = []
    for org in ("TeamFlow Cloud", "NovaMart Store"):
        for role in ("viewer", "agent", "owner"):
            checks.append(check_role(authenticate_gate(), org, role))
    print(json.dumps({"status":"PASS_PRIVATE_DEMO_ROLE_GUIDE_HTTP",
         "origin_type":"private_cloudflare_https" if PUBLIC else "loopback",
         "languages":["vi","en"],"organizations":2,"role_accounts":len(checks),
         "role_guides":3,"unauthenticated_blocked":True,
         "post_business_mutations":0,"secrets_logged":False,
         "checks":checks},indent=2))


if __name__ == "__main__":
    main()
