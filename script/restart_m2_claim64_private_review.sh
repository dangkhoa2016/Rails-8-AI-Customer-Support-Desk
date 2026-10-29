#!/usr/bin/env bash
# Reopen the OFFLINE, synthetic M2 claim64 reviewer workbook after Colab restarts.
# Runs only a password-protected localhost HTTP server and Cloudflare Quick Tunnel.
# NEVER print credentials, export them to Git, run a model, or change Rails DB.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
PRIVATE_DIR=/root/.config/rails8-support-desk-private-review
PRIVATE_KEY="$PRIVATE_DIR/preview-password.txt"
RUNTIME=/content/.m2-review-private-runtime
CLOUDFLARED="$RUNTIME/bin/cloudflared"
CLOUDFLARED_SHA256=1d356dac769d0dbf62ebe588c4034824bbff98d5790c2f844cc99e0e2f57462d
CLOUDFLARED_VERSION=2026.10.6
mkdir -p "$PRIVATE_DIR" "$RUNTIME/bin"
chmod 700 "$PRIVATE_DIR"
if [[ ! -s "$PRIVATE_KEY" ]]; then
  python3 - "$PRIVATE_KEY" <<'PY'
from pathlib import Path
import os
import secrets
import sys
p=Path(sys.argv[1])
if p.exists():
    raise SystemExit("Refusing to overwrite existing key")
fd=os.open(p,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
with os.fdopen(fd,"w") as out:
    out.write(secrets.token_urlsafe(48)+"\n")
print("NEW_PRIVATE_ACCESS_PASSWORD_WRITTEN_WITH_MODE_0600")
PY
else
  [[ "$(stat -c %a "$PRIVATE_KEY")" == "600" ]] || { echo "Unsafe access-key permissions"; exit 2; }
  echo "USING_EXISTING_PRIVATE_ACCESS_PASSWORD"
fi
for page in index.vi.html index.en.html sample-approval.vi.html sample-approval.en.html; do
  test -s "evidence-m2-claim64-independent-review-v2-20261029/$page"
done
if [[ ! -x "$CLOUDFLARED" ]] || ! echo "$CLOUDFLARED_SHA256  $CLOUDFLARED" | sha256sum -c --status; then
  echo "INSTALLING_PINNED_CLOUDFLARED_BINARY"
  curl --fail --location --silent --show-error --connect-timeout 20 --max-time 180 \
    "https://github.com/cloudflare/cloudflared/releases/download/$CLOUDFLARED_VERSION/cloudflared-linux-amd64" \
    -o "$CLOUDFLARED.tmp"
  echo "$CLOUDFLARED_SHA256  $CLOUDFLARED.tmp" | sha256sum -c --status || {
    rm -f "$CLOUDFLARED.tmp"; echo "Cloudflared digest mismatch"; exit 2;
  }
  chmod 755 "$CLOUDFLARED.tmp"
  mv "$CLOUDFLARED.tmp" "$CLOUDFLARED"
fi
echo "$CLOUDFLARED_SHA256  $CLOUDFLARED" | sha256sum -c --status
if ! curl --silent --max-time 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:3176/index.vi.html | grep -q '^401$'; then
  if ss -ltn | grep -q '127.0.0.1:3176 '; then
    echo "Port 3176 occupied by unexpected service; refusing to override"; exit 2
  fi
  nohup python3 -u script/serve_m2_claim64_workbook_private.py > "$RUNTIME/private-server.log" 2>&1 < /dev/null &
  echo "STARTED_PRIVATE_SERVER"
fi
for i in $(seq 1 12); do
  if [[ "$(curl --silent --max-time 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:3176/index.vi.html)" == "401" ]]; then break; fi
  sleep 1
done
test "$(curl --silent --max-time 4 -o /dev/null -w '%{http_code}' http://127.0.0.1:3176/index.vi.html)" = "401" || {
  echo "Local auth did not fail closed"; exit 2;
}
if ! pgrep -af 'cloudflared tunnel.*http://127.0.0.1:3176' | grep -q "$CLOUDFLARED"; then
  nohup "$CLOUDFLARED" tunnel --no-autoupdate --url http://127.0.0.1:3176 \
    > "$RUNTIME/private-tunnel.log" 2>&1 < /dev/null &
  echo "STARTED_NEW_CLOUDFLARE_TUNNEL"
fi
for i in $(seq 1 25); do
  if grep -Eq 'https://[a-z0-9-]+\.trycloudflare\.com' "$RUNTIME/private-tunnel.log" 2>/dev/null; then break; fi
  sleep 1
done
echo "REVIEW_URL_IF_TUNNEL_READY:"
grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' "$RUNTIME/private-tunnel.log" | sort -u | tail -n 1 || true
echo "USERNAME: review"
echo "PASSWORD_IS_NOT_DISPLAYED; view it privately on Colab with:"
echo "cat /root/.config/rails8-support-desk-private-review/preview-password.txt"
echo "DO_NOT_SHARE_PASSWORD_OR_COMMIT_EPHEMERAL_TUNNEL_URL"
