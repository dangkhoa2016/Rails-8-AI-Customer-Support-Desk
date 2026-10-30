#!/usr/bin/env bash
# Isolated P0.3 security hardening. Requires host PostgreSQL administrator.
# Never use on production or canonical development DB. Run after migrations.
set -euo pipefail
source /root/.config/rails8-support-desk-p03/sandbox.env
[[ "${P03_SANDBOX_MARKER:-}" == RAILS8_P03_ISOLATED_SANDBOX ]]
[[ "${P03_SANDBOX_LOCAL_ONLY:-}" == YES ]]
[[ "${PGDATABASE:-}" == rails8_p03_sandbox ]]
[[ "${PGUSER:-}" == rails8_p03_operator ]]
[[ "${PGPORT:-}" == 5432 ]]
[[ "${PGHOST:-}" == 127.0.0.1 ]]
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
run_as_pg() {
  runuser -u postgres -- env -u PGHOST -u PGUSER -u PGPASSWORD -u PGDATABASE -u PGPORT \
    psql -h /var/run/postgresql -p 5432 -X -v ON_ERROR_STOP=1 "$@"
}
test -f "$repo/script/p03_lockdown_audit_owner.sql"
test "$(run_as_pg -d postgres -qAt -c "SELECT COUNT(*) FROM pg_database WHERE datname='rails8_p03_sandbox'")" = 1
run_as_pg -d postgres -q <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='rails8_p03_audit_owner') THEN
    CREATE ROLE rails8_p03_audit_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
  END IF;
END;
$$;
ALTER DATABASE rails8_p03_sandbox OWNER TO postgres;
SQL
run_as_pg -d rails8_p03_sandbox -q -f "$repo/script/p03_lockdown_audit_owner.sql"
result="$(psql -d rails8_p03_sandbox -X -qAt -F "|" -c "
  SELECT pg_get_userbyid((SELECT relowner FROM pg_class WHERE relname='platform_security_events')),
         has_table_privilege(current_user,'platform_security_events','TRUNCATE'),
         has_table_privilege(current_user,'platform_security_events','INSERT')")"
test "$result" = "rails8_p03_audit_owner|f|t"
printf 'P03_AUDIT_OWNER_LOCKDOWN_PASS\n'
