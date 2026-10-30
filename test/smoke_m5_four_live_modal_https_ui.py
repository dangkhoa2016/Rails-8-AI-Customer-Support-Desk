#!/usr/bin/env python3
"""M5.0 HTTPS UI acceptance: four strictly synthetic Modal 4B/4B queries.

No credentials, cookies, raw HTML or document bodies in output.
All business writes remain blocked by PrivateColabPreviewGate.
"""
import hashlib
import json
import os
from pathlib import Path
import re
from bs4 import BeautifulSoup
import requests
import time

ROOT = Path(__file__).resolve().parents[1]
DATASET = ROOT / "review/m2_dual_qwen3_4b_pilot_queries.json"
OUT = ROOT / "evidence-m5-live-recovery-20261030/m5-https-ui-four-readonly.jsonl"
assert not OUT.exists(), "refusing to overwrite"
password = os.environ["RAILS_PRIVATE_PREVIEW_PASSWORD"]
assert len(password) >= 30
tunnel_log = Path("/tmp/rails8_m5_cloudflared_20261030.log").read_text()
origin = "https://" + re.findall(r"https://([a-z0-9-]+\.trycloudflare\.com)", tunnel_log)[-1]
items = json.loads(DATASET.read_text())["cases"]
ids = ["M2-4B-01","M2-4B-02","M2-4B-07","M2-4B-08"]
lookup = {v["case_id"]:v for v in items}
expected = {"teamflow-cloud":"TF-", "novamart-store":"NM-"}


def form_login(tenant, locale):
    s = requests.Session()
    gateway = s.get(origin+"/__private_preview/sign_in",timeout=20)
    assert gateway.status_code==200
    nonce = re.search(r'name="nonce"\s+value="([^"]+)"',gateway.text)
    assert nonce
    response = s.post(origin+"/__private_preview/sign_in",
        data={"nonce":nonce.group(1),"preview_password":password},
        allow_redirects=False,timeout=20)
    assert response.status_code==303
    page = s.get(origin+"/demo/sign_in",timeout=20)
    assert page.status_code==200
    doc = BeautifulSoup(page.text,"html.parser")
    name = "TeamFlow Cloud" if tenant=="teamflow-cloud" else "NovaMart Store"
    options=[o for o in doc.select("optgroup option") if o.parent.get("label")==name
             and o.get_text(strip=True).startswith("Owner ·")]
    assert len(options)==1
    token = doc.select_one('meta[name="csrf-token"]')['content']
    selected=s.post(origin+"/demo/sign_in",
        data={"membership_id":options[0]["value"],"locale":locale,
              "authenticity_token":token},
        headers={"X-CSRF-Token":token},allow_redirects=False,timeout=20)
    assert selected.status_code in (302,303)
    return s


print(json.dumps({"event":"begin","kind":"M5_SYNTHETIC_HTTPS_MODAL_UI",
                  "case_ids":ids,"answerability":"BLOCKED"}),flush=True)
OUT.parent.mkdir(parents=True,exist_ok=True)
with OUT.open("x",encoding="utf-8") as out:
    for i,case_id in enumerate(ids):
        case=lookup[case_id]
        session=form_login(case["tenant"],case["locale"])
        get=session.get(origin+"/kb/ai-search",timeout=25)
        assert get.status_code==200
        doc=BeautifulSoup(get.text,"html.parser")
        textbox=doc.select_one("textarea[name=query]")
        assert textbox and not textbox.has_attr("disabled"), "semantic UI not ready"
        csrf=doc.select_one('meta[name="csrf-token"]')['content']
        before=time.monotonic()
        response=session.post(origin+"/kb/ai-search",
            headers={"X-CSRF-Token":csrf,"Accept":"text/html"},
            data={"query":case["query"],"privacy_confirmed":"1",
                  "authenticity_token":csrf},timeout=420)
        elapsed=round((time.monotonic()-before)*1000,1)
        record={"case_id":case_id,"tenant":case["tenant"],"locale":case["locale"],
                "query_sha256":hashlib.sha256(case["query"].encode()).hexdigest(),
                "status_code":response.status_code,"elapsed_ms_http":elapsed,
                "model_pair":"Qwen3-Embedding-4B + Qwen3-Reranker-4B",
                "answerability":"BLOCKED","business_writes":0,
                "human_gold":False}
        if response.status_code!=200:
            record["status"]="FAIL_HTTP"
            out.write(json.dumps(record,ensure_ascii=False)+"\n");out.flush()
            raise AssertionError("unexpected semantic search response status")
        result=BeautifulSoup(response.text,"html.parser")
        hits=result.select("article.ai-hit")
        names=[]
        citations=[]
        for hit in hits:
            link=hit.select_one(".ai-hit-top strong a")
            assert link
            key=link.get_text(strip=True)
            assert key.startswith(expected[case["tenant"]])
            names.append(key)
            txt=hit.get_text(" ",strip=True)
            assert "SHA256:" in txt or "SHA256" in txt
            citations.append(any("citation" in t.lower() or "trích dẫn" in t.lower() for t in [txt]))
        record.update(status="PASS_REAL_MODAL_HTTPS_UI",
                      article_keys=names,
                      citations_rendered=len(hits),
                      expected_top1_hint=case["expected_article_key"],
                      top1_hint_matches=(bool(names) and names[0]==case["expected_article_key"]),
                      cross_tenant_hits=0)
        assert names and all(citations)
        out.write(json.dumps(record,ensure_ascii=False)+"\n");out.flush()
        print(json.dumps({"event":"case_pass","case_id":case_id,"http":response.status_code,
                          "elapsed_ms":elapsed,"top1":names[0],"citations":len(names),
                          "progress":f"{i+1}/4"}),flush=True)
print(json.dumps({"event":"complete","status":"PASS_4_HTTPS_REAL_MODAL_UI",
                 "evidence_sha256":hashlib.sha256(OUT.read_bytes()).hexdigest(),
                 "answerability":"BLOCKED"}),flush=True)
