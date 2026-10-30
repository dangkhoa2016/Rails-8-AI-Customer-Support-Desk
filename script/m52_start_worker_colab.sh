#!/usr/bin/env bash
# Synthetic Colab M5.2 only; no tokens in source repository.
set -euo pipefail
source /content/rails8_restore_env_20261030.sh
set -a
source /root/.config/rails8-support-desk-modal/rails-client.env
set +a
export RAILS_ENV=development
export RAILS_PRIVATE_PREVIEW=NO
export M5_ASYNC_SEARCH_ENABLE=YES M2_SEMANTIC_UI_ENABLE=YES
export M2_ANSWERABILITY_SCOPE_ENABLE=NO
test -n "${MODAL_PROXY_KEY:-}" && test -n "${MODAL_RERANK_TOKEN:-}"
exec bin/jobs start
