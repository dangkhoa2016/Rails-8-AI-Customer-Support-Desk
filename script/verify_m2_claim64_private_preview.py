#!/usr/bin/env python3
"""External, read-only acceptance for the private M2 claim64 workbook tunnel.
Never prints, stores, or hashes the password. Does not test policy correctness.
"""
from pathlib import Path
from datetime import datetime,timezone
import argparse
import hashlib
import json
import re
import requests
import sys

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/"evidence-m2-claim64-independent-review-v2-20261029"
SECRET=Path("/root/.config/rails8-support-desk-private-review/preview-password.txt")

def validate(origin):
    assert re.fullmatch(r"https://[a-z0-9-]+\.trycloudflare\.com",origin),"Unsafe origin"
    key=SECRET.read_text().strip()
    assert len(key)>=40 and (SECRET.stat().st_mode&0o777)==0o600,"Invalid secret permissions"
    session=requests.Session()
    unauth=session.get(origin+"/index.vi.html",timeout=20)
    assert unauth.status_code==401,"Authentication bypass"
    success={}
    for lang in ("vi","en"):
        resource=f"/index.{lang}.html"
        r=session.get(origin+resource,auth=("review",key),timeout=20)
        local=(SOURCE/f"index.{lang}.html").read_bytes()
        assert r.status_code==200 and r.content==local,lang+": body drift"
        assert r.content.count(b'<article class="task"')==64
        assert r.content.count(b'<details class="kb"')==12
        assert "no-store" in r.headers.get("Cache-Control","")
        assert "connect-src 'none'" in r.headers.get("Content-Security-Policy","")
        assert r.headers.get("X-Frame-Options")=="DENY"
        success[lang]={"http":200,"bytes":len(local),
            "content_sha256":hashlib.sha256(local).hexdigest(),
            "claim_cards":64,"kb_articles":12}
    forbidden={}
    for path in ("/.env.notebook","/script/compare_m2_dual_external_reviews.py",
        "/checkpoints/RAILS8_M2_CLAIM64_REVIEW_V2_REBOOT_RECOVERY_LOCAL_DELTA_20261029.zip"):
        response=session.get(origin+path,auth=("review",key),timeout=20)
        assert response.status_code==404,"Forbidden content accessible"
        forbidden[path]=404
    methods={}
    for method in ("POST","PUT","DELETE"):
        response=session.request(method,origin+"/index.vi.html",auth=("review",key),timeout=20)
        assert response.status_code==405,"Writes not blocked"
        methods[method]=405
    return {"kind":"M2_CLAIM64_READONLY_PRIVATE_TUNNEL_RESTART_ACCEPTANCE",
      "verified_utc":datetime.now(timezone.utc).isoformat(),
      "status":"PASS_AUTH_HASH_ALLOWLIST_METHOD_RESTRICTIONS",
      "connection":"CLOUDFLARE_QUICK_TUNNEL_HTTPS",
      "tunnel_url_saved":False,
      "credential_content_saved":False,
      "unauthorized_get_status":401,
      "authorized_workbooks":success,
      "other_paths":forbidden,"write_methods":methods,
      "private_password_mode":"0600",
      "reviewers_received":0,"human_semantic_gold":"NOT_RUN",
      "model_gpu_inference":"NOT_RUN","release":"BLOCKED"}

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--origin",required=True)
    parser.add_argument("--output",type=Path)
    args=parser.parse_args()
    try:
        result=validate(args.origin)
        report=json.dumps(result,indent=2,ensure_ascii=False)+"\n"
        if args.output:
            assert not args.output.exists(),"Refusing to overwrite old evidence"
            args.output.parent.mkdir(parents=True,exist_ok=True)
            args.output.write_text(report)
        print(report,end="")
    except (AssertionError,ValueError,FileNotFoundError,requests.RequestException) as exc:
        print(json.dumps({"status":"FAILED_CLOSED","failure_type":type(exc).__name__,
          "reason":str(exc)[:150],"release":"BLOCKED"}))
        sys.exit(2)
if __name__=="__main__":main()
