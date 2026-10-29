#!/usr/bin/env bash
# Provision Rails 8 + PostgreSQL on a disposable Kaggle/Colab Ubuntu notebook.
# Requires network access and apt permissions; does not create a public tunnel.
# Generates a LOCAL dev DB password stored in .env.notebook (git-ignored).
set -Eeuo pipefail
cd "$(dirname "$0")/.."
if [[ "$(id -u)" != 0 ]]; then echo 'Run notebook setup as root (default on Kaggle/Colab)' >&2; exit 2; fi
if [[ -z "${KAGGLE_KERNEL_RUN_TYPE:-}" && -z "${COLAB_GPU:-}" && ! -d /kaggle && ! -d /content ]]; then
  echo 'Expected Kaggle/Colab environment; refusing unattended machine changes.' >&2; exit 2
fi
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates git build-essential pkg-config libssl-dev libreadline-dev zlib1g-dev libyaml-dev libffi-dev libpq-dev postgresql postgresql-client
if [[ ! -x /root/.local/bin/mise ]]; then
  curl --fail --location --silent --show-error https://mise.run | sh
fi
export PATH="/root/.local/bin:$PATH"
# Exact Ruby 3.3 is selected, patch revision may differ across notebook dates.
mise install ruby@3.3
RUBY_DIR="$(mise where ruby@3.3)"
export PATH="$RUBY_DIR/bin:$PATH"
ruby -v
bundle -v
bundle config set --local path vendor/bundle
bundle install
service postgresql start
# Local synthetic-only PostgreSQL account; password must never be put in evidence or Git.
if [[ ! -f .env.notebook ]]; then
  secret="$(openssl rand -hex 24)"
  printf 'PGHOST=127.0.0.1\nPGPORT=5432\nPGUSER=support_desk\nPGPASSWORD=%s\nPGDATABASE=rails8_ai_support_desk_development\nM1_SYNTHETIC_DEMO=YES\nRAILS_ENV=development\n' "$secret" > .env.notebook
  chmod 600 .env.notebook
fi
# Provision role using a privileged local Unix-socket connection, NEVER the
# application PGUSER/PGPASSWORD. Supports rerun after a partially failed setup.
bash script/repair_notebook_postgres.sh
echo 'Ready. Next commands: source script/use_notebook_env.sh; bash script/run_full_m1.sh; bash script/run_full_m2.sh; bin/rails server -b 127.0.0.1 -p 3000'
