#!/usr/bin/env bash
# Run only with a fresh, exact Cloudflare Quick Tunnel hostname.
# The externally protected preview is still business read-only.
set -euo pipefail
source /content/rails8_restore_env_20261030.sh
set -a
source /root/.config/rails8-support-desk-modal/rails-private-preview.env
source /root/.config/rails8-support-desk-modal/rails-client.env
set +a
export RAILS_ENV=development RAILS_PRIVATE_PREVIEW=YES
export RAILS_TUNNEL_READ_ONLY=YES M5_ASYNC_SEARCH_ENABLE=YES
export M2_SEMANTIC_UI_ENABLE=YES M2_ANSWERABILITY_SCOPE_ENABLE=NO
if [[ ! "${RAILS_PREVIEW_TUNNEL_HOST:-}" =~ ^[a-z0-9-]+\.trycloudflare\.com$ ]]; then
  echo 'Provide exact RAILS_PREVIEW_TUNNEL_HOST for this runtime' >&2
  exit 2
fi
test -n "${RAILS_PRIVATE_PREVIEW_PASSWORD:-}"
exec bin/rails server -b 127.0.0.1 -p 3068 -e development
