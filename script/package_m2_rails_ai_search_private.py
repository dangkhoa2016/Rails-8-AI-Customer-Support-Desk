#!/usr/bin/env python3
"""Checkpoint live local-only Rails UI; never include API tokens or dev auth code."""
import datetime
import hashlib
import json
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "checkpoints"
DB = OUT / "M2_RAILS_AI_SEARCH_PRIVATE_SYNTHETIC_DB_20261029.dump"
SOURCE = OUT / "RAILS8_M2_RAILS_AI_SEARCH_PRIVATE_SOURCE_20261029.zip"
EVIDENCE = OUT / "RAILS8_M2_RAILS_AI_SEARCH_PRIVATE_EVIDENCE_20261029.zip"
MASTER = OUT / "RAILS8_M2_RAILS_AI_SEARCH_PRIVATE_CHECKPOINT_20261029.zip"
MANIFEST = OUT / "M2_RAILS_AI_SEARCH_PRIVATE_CHECKPOINT_MANIFEST.json"
SUMS = OUT / "M2_RAILS_AI_SEARCH_PRIVATE_SHA256SUMS.txt"
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
excluded = {"checkpoints", ".git", "__pycache__", ".bundle", "bundle", "vendor",
            "node_modules", "tmp", "log", ".cache"}
files = []
for dirname in ("app", "bin", "config", "data", "db", "docs", "modal_app", "preview", "review", "script", "test"):
    for f in (ROOT / dirname).rglob("*"):
        rel = f.relative_to(ROOT)
        if (f.is_file() and not any(part in excluded or part.startswith(".env") for part in rel.parts)
                and f.suffix not in (".log", ".dump", ".zip", ".pyc")
                and f.name not in ("master.key", "credentials.yml.enc")):
            files.append(f)
for name in ("README_VI.md", "README_EN.md", "Gemfile", "Gemfile.lock", "Rakefile",
             "Dockerfile", "config.ru", ".ruby-version", ".gitignore", ".dockerignore"):
    f = ROOT / name
    if f.is_file():
        files.append(f)
files = sorted(set(files))
evidence_files = sorted(set(
    [p for p in (ROOT / "evidence-m2-rails-ui-live-20261029").rglob("*") if p.is_file()] +
    [p for p in (OUT / "evidence-m2-rails-ui-private-20261029").rglob("*") if p.is_file()]
))
assert len(evidence_files) >= 3 and DB.is_file() and DB.stat().st_size > 100_000
known_secrets = []
for path in list((Path.home() / ".config/rails8-support-desk-modal").glob("*.env")) + [
    Path.home() / ".kaggle/access_token"
]:
    if path.is_file():
        for line in path.read_text(errors="replace").splitlines():
            maybe = line.partition("=")[2] if "=" in line else line
            if len(maybe) >= 24:
                known_secrets.append(maybe.encode("utf-8"))
for f in files + evidence_files:
    content = f.read_bytes()
    assert not any(secret in content for secret in known_secrets), "Credential in archive input: " + str(f)
with zipfile.ZipFile(SOURCE, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for f in files:
        z.write(f, f.relative_to(ROOT).as_posix())
with zipfile.ZipFile(EVIDENCE, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for f in evidence_files:
        z.write(f, f.relative_to(ROOT).as_posix())
live = json.loads((ROOT / "evidence-m2-rails-ui-live-20261029/rails-ui-live-results.json").read_text())
gate = json.loads((ROOT / "evidence-m2-rails-ui-live-20261029/preview-gate-acceptance.json").read_text())
assert live["status"] == "PASS_LIVE_RAILS_UI_VI_EN" and len(live["cases"]) == 2
assert gate["status"] == "PASS_PRIVATE_PREVIEW_GATE_RAILS_UI_NO_GPU"
assert all(c["top1"] == c["expected_article"] for c in live["cases"])
report = {
    "status": "PASS_LOCAL_RAILS_AI_SEARCH_4B_4B_WITH_PRIVATE_PREVIEW_GATE",
    "captured_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "device": "306682c8dabe",
    "modal_environment": "rails-8-ai-customer-support-desk",
    "rails_bind": "127.0.0.1:3068",
    "rails_environment": "development",
    "private_preview_basic_auth": "ENABLED_STRONG_PASSWORD_OUTSIDE_REPOSITORY",
    "colab_browser_proxy": "USER_BROWSER_NOT_TESTED",
    "cloudflare_rails": "NOT_EXPOSED",
    "m0_m1": "UNCHANGED",
    "approved_kb_versions": 12, "stored_real_embeddings": 84,
    "live_ui_queries": len(live["cases"]),
    "live_ui_top1": "2/2",
    "live_ui_request_ms": [item["request_elapsed_ms"] for item in live["cases"]],
    "private_preview_gate_http_cases": len(gate["checks"]),
    "rails_regression": "40 tests, 475 assertions, 0 failures/errors/skips",
    "source_files": len(files), "evidence_files": len(evidence_files),
    "source_zip_sha256": sha(SOURCE), "evidence_zip_sha256": sha(EVIDENCE),
    "database_dump_sha256": sha(DB),
    "secrets_packaged": False,
    "model_upstream": {
        "embedding": "Qwen/Qwen3-Embedding-4B@5cf2132abc99cad020ac570b19d031efec650f2b",
        "reranker": "Qwen/Qwen3-Reranker-4B@22e683669bc0f0bd69640a1354a6d0aebcfeede5"
    }
}
MANIFEST.write_text(json.dumps(report, indent=2) + "\n")
with zipfile.ZipFile(MASTER, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for p in (SOURCE, EVIDENCE, DB, MANIFEST):
        z.write(p, p.name)
for p in (SOURCE, EVIDENCE, MASTER):
    with zipfile.ZipFile(p) as z:
        assert z.testzip() is None
        assert not any("/.env" in n or n.startswith(".env") or "master.key" in n or "rails-private-preview.env" in n for n in z.namelist())
SUMS.write_text("".join(f"{sha(p)}  {p.name}\n" for p in (SOURCE, EVIDENCE, DB, MANIFEST, MASTER)))
print(json.dumps({"master": MASTER.name, "bytes": MASTER.stat().st_size,
                  "sha256": sha(MASTER), "files": len(files), "evidence_files": len(evidence_files),
                  "status": report["status"]}, indent=2))
