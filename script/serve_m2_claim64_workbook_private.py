#!/usr/bin/env python3
"""Secure static-only preview of synthetic M2 claim64 reviewer workbooks.
Loopback only, Cloudflare Quick Tunnel + Basic HTTPS auth, two HTML paths.
No uploads, dynamic routes, model calls or business/DB writes.
"""
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
import base64
import hmac
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]/"evidence-m2-claim64-independent-review-v2-20261029"
SECRET=Path("/root/.config/rails8-support-desk-private-review/preview-password.txt")
if not SECRET.is_file():raise SystemExit("Missing private preview password file")
password=SECRET.read_text().strip()
if len(password.encode())<40:raise SystemExit("Private password too short")
PAGES={"/":"sample-approval.vi.html",
       "/sample-approval.vi.html":"sample-approval.vi.html",
       "/sample-approval.en.html":"sample-approval.en.html",
       "/index.vi.html":"index.vi.html",
       "/index.en.html":"index.en.html"}
allowed_host=re.compile(r"^(127\.0\.0\.1|localhost|[a-z0-9-]+\.trycloudflare\.com)$")
expected="Basic "+base64.b64encode(("review:"+password).encode()).decode()
for p in set(PAGES.values()):
    assert (ROOT/p).is_file() and (ROOT/p).stat().st_size<400000

class Handler(BaseHTTPRequestHandler):
    server_version="M2SyntheticReviewerPrivate/1"
    sys_version=""
    def log_message(self,fmt,*args):
        # Do not log credentials, authorization headers or query parameters.
        print("PRIVATE_REVIEW",self.command,self.path.split("?")[0],flush=True)
    def headers_out(self,code,length=0,content_type="text/plain; charset=utf-8",auth=False):
        self.send_response(code)
        self.send_header("Content-Length",str(length))
        self.send_header("Content-Type",content_type)
        self.send_header("Cache-Control","private, no-store")
        self.send_header("X-Content-Type-Options","nosniff")
        self.send_header("X-Frame-Options","DENY")
        self.send_header("Referrer-Policy","no-referrer")
        self.send_header("Content-Security-Policy",
            "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; "
            "connect-src 'none'; img-src 'none'; base-uri 'none'; form-action 'none'")
        if auth:self.send_header("WWW-Authenticate",'Basic realm="Private M2 Claim64 Reviewer"')
        self.end_headers()
    def do_GET(self):self.deliver()
    def do_HEAD(self):self.deliver(head=True)
    def do_POST(self):self.headers_out(405)
    def do_PUT(self):self.headers_out(405)
    def do_DELETE(self):self.headers_out(405)
    def deliver(self,head=False):
        host=self.headers.get("Host","").split(":")[0].lower()
        if not allowed_host.fullmatch(host):
            self.headers_out(403);return
        if not hmac.compare_digest(self.headers.get("Authorization",""),expected):
            self.headers_out(401,auth=True);return
        path=self.path.split("?",1)[0]
        if path not in PAGES:
            self.headers_out(404);return
        contents=(ROOT/PAGES[path]).read_bytes()
        self.headers_out(200,len(contents),"text/html; charset=utf-8")
        if not head:self.wfile.write(contents)

if __name__=="__main__":
    print("SYNTHETIC_DEMO_PRIVATE_LISTENER_READY bind=127.0.0.1:3176 sample_pages=2 optional_review_pages=2 secret_not_printed",flush=True)
    ThreadingHTTPServer(("127.0.0.1",3176),Handler).serve_forever()
