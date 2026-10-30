#!/usr/bin/env bash
# Password-protected, business read-only Cloudflare Quick Tunnel preview on 3068.
# Tunnel process and exact generated hostname must be prepared separately.
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo/script/rails8_runtime_ruby.sh"
db_env="/root/.config/rails8-support-desk-modal/rails8-db.env"
preview_env="/root/.config/rails8-support-desk-modal/rails-private-preview.env"
if [[ ! -r "$db_env" || ! -r "$preview_env" ]]; then
  echo 'PRIVATE_PREVIEW_ERROR: local database/preview environment missing' >&2
  exit 1
fi
set -a
source "$db_env"
source "$preview_env"
set +a
[[ "${PGDATABASE:-}" == rails8_ai_support_desk_development ]]
[[ "${PGUSER:-}" == support_desk ]]
[[ "${PGHOST:-}" == 127.0.0.1 ]]
if [[ ! "${RAILS_PREVIEW_TUNNEL_HOST:-}" =~ ^[a-z0-9-]+\.trycloudflare\.com$ ]]; then
  echo 'PRIVATE_PREVIEW_ERROR: exact Cloudflare Quick Tunnel hostname required' >&2
  exit 2
fi
if (( ${#RAILS_PRIVATE_PREVIEW_PASSWORD} < 30 )); then
  echo 'PRIVATE_PREVIEW_ERROR: password too short' >&2
  exit 2
fi
# Explicitly prohibit model inference, GPU jobs, and mutable search runs on the public preview.
export RAILS_ENV=development
export RAILS_PRIVATE_PREVIEW=YES RAILS_TUNNEL_READ_ONLY=YES
export RAILS_PREVIEW_AI_SEARCH_ALLOW=NO
export M5_ASYNC_SEARCH_ENABLE=NO M2_SEMANTIC_UI_ENABLE=NO M2_ANSWERABILITY_SCOPE_ENABLE=NO
unset MODAL_EMBEDDING_URL MODAL_EMBEDDING_TOKEN MODAL_RERANK_URL MODAL_RERANK_TOKEN \
  MODAL_PROXY_KEY MODAL_PROXY_SECRET || true
cd "$repo"
exec bundle exec rails server --binding 127.0.0.1 --port 3068 --environment development
