#!/usr/bin/env python3
"""Reproducible external checks for sample-only approval preview.
No business writes, no password or ephemeral URL in evidence output.
"""
from pathlib import Path
from datetime import datetime,timezone
import argparse,hashlib,json,re,sys
import requests
ROOT=Path(__file__).resolve().parents[1]
SECRET=Path("/root/.config/rails8-support-desk-private-review/preview-password.txt")
PAGES=ROOT/"evidence-m2-claim64-independent-review-v2-20261029"
CASES={
 "/":"sample-approval.vi.html",
 "/sample-approval.vi.html":"sample-approval.vi.html",
 "/sample-approval.en.html":"sample-approval.en.html",
 "/index.vi.html":"index.vi.html",
 "/index.en.html":"index.en.html"
}
def run(origin):
    assert re.fullmatch(r"https://[a-z0-9-]+\.trycloudflare\.com",origin)
    assert SECRET.is_file() and SECRET.stat().st_mode&0o777==0o600
    password=SECRET.read_text().strip()
    assert len(password)>=40
    sess=requests.Session()
    assert sess.get(origin+"/",timeout=20).status_code==401
    response={}
    for path,file in CASES.items():
        obj=sess.get(origin+path,auth=("review",password),timeout=20)
        local=(PAGES/file).read_bytes()
        assert obj.status_code==200 and obj.content==local
        assert "no-store" in obj.headers.get("Cache-Control","")
        assert "connect-src 'none'" in obj.headers.get("Content-Security-Policy","")
        response[path]={"http":200,"bytes":len(local),"sha256":hashlib.sha256(local).hexdigest()}
    for url in ("/.env.notebook","/review/m2_claim64_synthetic_demo_approval_20261029.json",
                "/script/serve_m2_claim64_workbook_private.py"):
        assert sess.get(origin+url,auth=("review",password),timeout=20).status_code==404
    for method in ("POST","PUT","DELETE"):
        assert sess.request(method,origin+"/sample-approval.vi.html",
          auth=("review",password),timeout=20).status_code==405
    return {"kind":"M2_OWNER_APPROVED_SYNTHETIC_DEMO_PRIVATE_PREVIEW_ACCEPTANCE",
      "verified_utc":datetime.now(timezone.utc).isoformat(),
      "status":"PASS_HTTP_AND_BYTE_INTEGRITY",
      "origin_url_saved":False,"password_saved":False,
      "unauthenticated_status":401,"pages":response,"forbidden_paths":404,
      "business_write_methods_status":405,
      "demo_sample_status":"APPROVED_FOR_SYNTHETIC_DEMO",
      "all_claims_approved_for_sample_presentation":64,
      "independent_human_semantic_signoff":"NOT_PERFORMED_NOT_REQUIRED_FOR_SAMPLE_DISPLAY",
      "automatic_policy_answerability":"BLOCKED",
      "ai_business_writes":"PROHIBITED"}
if __name__=="__main__":
    cli=argparse.ArgumentParser()
    cli.add_argument("--origin",required=True)
    cli.add_argument("--output",type=Path)
    a=cli.parse_args()
    try:
        report=run(a.origin);body=json.dumps(report,ensure_ascii=False,indent=2)+"\n"
        if a.output:
            assert not a.output.exists()
            a.output.parent.mkdir(parents=True,exist_ok=True)
            a.output.write_text(body)
        print(body,end="")
    except (AssertionError,FileNotFoundError,requests.RequestException,ValueError) as e:
        print(json.dumps({"status":"FAIL_CLOSED","reason":str(e)[:150]}));sys.exit(2)
