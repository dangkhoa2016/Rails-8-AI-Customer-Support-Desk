#!/usr/bin/env bash
# Fix PostgreSQL authentication on a disposable Kaggle/Colab synthetic demo.
# Safe on repeated invocations: preserves .env.notebook and existing databases.
# Never include database passwords in commands, stdout/stderr or evidence files.
set -Eeuo pipefail
cd "$(dirname "$0")/.."
if [[ "$(id -u)" != 0 ]]; then
  echo 'This notebook repair must run as root (Kaggle/Colab default).' >&2
  exit 2
fi
if [[ -z "${KAGGLE_KERNEL_RUN_TYPE:-}" && -z "${COLAB_GPU:-}" && ! -d /kaggle && ! -d /content ]]; then
  echo 'Refusing to change PostgreSQL outside a Kaggle/Colab notebook.' >&2
  exit 2
fi
if [[ ! -f .env.notebook ]]; then
  echo 'Missing .env.notebook. Run script/notebook_setup.sh first.' >&2
  exit 2
fi
# Read local, git-ignored credentials without logging their contents.
set -a
# shellcheck disable=SC1091
source .env.notebook
set +a
if [[ "${M1_SYNTHETIC_DEMO:-}" != YES || "${RAILS_ENV:-}" != development ]]; then
  echo 'Repair permitted only for the synthetic Rails development database.' >&2
  exit 3
fi
if [[ -z "${PGPASSWORD:-}" || "${PGUSER:-}" != support_desk || "${PGHOST:-}" != 127.0.0.1 || "${PGPORT:-}" != 5432 ]]; then
  echo 'Unexpected PostgreSQL demo credentials/host; refusing to alter database roles.' >&2
  exit 3
fi
if [[ ! -x /usr/bin/psql ]] || ! command -v runuser >/dev/null 2>&1; then
  echo 'PostgreSQL client or runuser missing. Run notebook_setup.sh first.' >&2
  exit 2
fi
# env -i removes inherited PGHOST, PGUSER, PGDATABASE, PGPASSWORD, PGOPTIONS,
# PGSERVICE etc., which otherwise override the postgres OS identity.
admin_psql() {
  runuser -u postgres -- env -i PATH=/usr/bin:/bin LANG=C \
    /usr/bin/psql -X -w -h /var/run/postgresql -p 5432 -U postgres -d postgres \
    -v ON_ERROR_STOP=1 "$@"
}
# Must use local peer auth as the OS postgres account. This cannot accidentally
# authenticate through TCP as support_desk.
if ! admin_psql -qAt -c 'SELECT current_user' | grep -qx postgres; then
  echo 'Local postgres superuser/peer authentication failed. Check local cluster.' >&2
  exit 4
fi
if [[ "$(admin_psql -qAt -c "SELECT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='support_desk')")" != t ]]; then
  printf 'CREATE ROLE support_desk WITH LOGIN CREATEDB;\n' | admin_psql -q
fi
# SQL literal escaping; secrets are sent on stdin, not displayed in process args.
password_literal="'${PGPASSWORD//\'/\'\'}'"
printf 'ALTER ROLE support_desk WITH LOGIN CREATEDB PASSWORD %s;\n' "$password_literal" | admin_psql -q
unset password_literal
# Verify exactly the connection Rails will use, without exposing the password.
if ! env -i PATH=/usr/bin:/bin LANG=C PGPASSWORD="$PGPASSWORD" \
  /usr/bin/psql -X -w -h 127.0.0.1 -p 5432 -U support_desk -d postgres \
  -v ON_ERROR_STOP=1 -qAt -c 'SELECT current_user' | grep -qx support_desk; then
  echo 'Application TCP authentication failed even after resetting the role.' >&2
  exit 5
fi
unset PGPASSWORD
printf 'PASS: postgres local peer admin + support_desk TCP password authentication.\n'
printf 'No databases were dropped/reset; credentials are unchanged in .env.notebook.\n'
