# shellcheck shell=bash
# Use: source script/use_notebook_env.sh  (do not execute in subshell)
M1_APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/root/.local/bin:${PATH}"
if command -v mise >/dev/null 2>&1; then
  M1_RUBY_DIR="$(mise where ruby@3.3)" || return 1
  export PATH="$M1_RUBY_DIR/bin:$PATH"
fi
if [[ ! -f "$M1_APP_ROOT/.env.notebook" ]]; then echo 'Missing .env.notebook; run script/notebook_setup.sh first' >&2; return 1; fi
set -a
# shellcheck disable=SC1091
source "$M1_APP_ROOT/.env.notebook"
set +a
