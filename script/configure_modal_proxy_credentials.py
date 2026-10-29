#!/usr/bin/env python3
"""Configure protected local Rails client from Modal CLI Proxy Token JSON.

Support Modal's version-dependent JSON field names and nesting. Do not print,
upload, or include credentials in project files, logs, or backups.
"""
import argparse
import json
import os
from pathlib import Path
import re

TOKEN_ID = re.compile(r"wk-[A-Za-z0-9_-]+")
TOKEN_SECRET = re.compile(r"ws-[A-Za-z0-9_-]+")


def read_pair(data):
    # Walk only values, never infer tokens from JSON field names.
    candidates = []
    def walk(value):
        if isinstance(value, dict):
            for child in value.values():
                walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)
        elif isinstance(value, str):
            candidates.append(value.strip())
    walk(data)
    ids = {v for v in candidates if TOKEN_ID.fullmatch(v)}
    secrets = {v for v in candidates if TOKEN_SECRET.fullmatch(v)}
    # Some CLI versions may return a combined wk-...ws-... token.
    if not ids and not secrets:
        combined = [v for v in candidates if re.fullmatch(
            r"wk-[A-Za-z0-9_-]+[.]ws-[A-Za-z0-9_-]+", v)]
        if len(combined) == 1:
            a, b = combined[0].split(".", 1)
            ids.add(a)
            secrets.add(b)
    if len(ids) != 1 or len(secrets) != 1:
        raise ValueError("Expected one distinct wk-/ws- proxy token pair in Modal JSON.")
    return next(iter(ids)), next(iter(secrets))


def configure(source):
    source = Path(source).expanduser().resolve()
    target_dir = Path.home() / ".config" / "rails8-support-desk-modal"
    if not source.is_file() or source.stat().st_mode & 0o077:
        raise ValueError("Proxy token JSON missing or accessible to group/other.")
    key, secret = read_pair(json.loads(source.read_text()))
    target = target_dir / "rails-client.env"
    if not target.is_file() or target.stat().st_mode & 0o077:
        raise ValueError("Rails client configuration missing or insecure.")
    existing = [line for line in target.read_text().splitlines()
                if not line.startswith(("MODAL_PROXY_KEY=", "MODAL_PROXY_SECRET="))]
    existing += ["MODAL_PROXY_KEY=" + key, "MODAL_PROXY_SECRET=" + secret]
    # Create fresh file atomically, no secret on command line.
    temporary = target_dir / "rails-client.env.new"
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "w") as file:
            file.write("\n".join(existing) + "\n")
        os.replace(temporary, target)
    finally:
        if temporary.exists():
            temporary.unlink()
    print("LOCAL_PROXY_CONFIG_READY; credentials hidden; GPU UI still opt-in.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--token-file", required=True)
    args = parser.parse_args()
    try:
        configure(args.token_file)
    except (ValueError, OSError, json.JSONDecodeError) as exc:
        raise SystemExit("Proxy configuration not changed: " + str(exc))
