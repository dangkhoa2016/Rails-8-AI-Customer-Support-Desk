#!/usr/bin/env bash
# Isolated localhost-only P0.3 sandbox; NEVER forward port 3078 to the Internet.
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo/script/rails8_runtime_ruby.sh"
sandbox_env="/root/.config/rails8-support-desk-p03/sandbox.env"
if [[ ! -r "$sandbox_env" ]]; then
  echo 'P03_SANDBOX_ERROR: required sandbox env file is missing' >&2
  exit 1
fi
set -a
source "$sandbox_env"
set +a
[[ "${P03_SANDBOX_MARKER:-}" == RAILS8_P03_ISOLATED_SANDBOX ]]
[[ "${P03_SANDBOX_LOCAL_ONLY:-}" == YES ]]
[[ "${PGDATABASE:-}" == rails8_p03_sandbox ]]
[[ "${PGUSER:-}" == rails8_p03_operator ]]
[[ "${PGHOST:-}" == 127.0.0.1 ]]
[[ "${PGPORT:-}" == 5432 ]]
[[ "${P0_PLATFORM_AUTH_ENABLE:-}" == YES ]]
[[ ! -e /content/.rails8-private-runtime/p03_sandbox_public_tunnel ]]
export RAILS_ENV=sandbox
cd "$repo"
exec bundle exec rails server --binding 127.0.0.1 --port 3078
