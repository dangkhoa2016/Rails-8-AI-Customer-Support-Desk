#!/usr/bin/env bash
# Run on an authorized disposable SYNTHETIC Rails 8/PostgreSQL development database only.
# Non-destructive: no db:drop or database resets. Fails closed if DB isn't empty M1 demo.
set -Eeuo pipefail
APP_DIR="${1:-}"
EVIDENCE="${2:-}"
[[ -n "$APP_DIR" && -n "$EVIDENCE" ]] || { echo 'Usage: run_m1_on_rails.sh RAILS_APP_PATH EVIDENCE_OUTPUT_DIR' >&2; exit 2; }
APP_DIR="$(cd "$APP_DIR" && pwd)"
mkdir -p "$EVIDENCE"
EVIDENCE="$(cd "$EVIDENCE" && pwd)"
[[ -f "$APP_DIR/data/m1_business_records.json" ]] || { echo 'Missing prepared M1 data in Rails app' >&2; exit 2; }
[[ -f "$APP_DIR/bin/rails" ]] || { echo 'Rails app not prepared' >&2; exit 2; }
[[ "${M1_SYNTHETIC_DEMO:-}" == 'YES' ]] || { echo 'Set M1_SYNTHETIC_DEMO=YES only for a disposable demo DB' >&2; exit 3; }
if [[ "${RAILS_ENV:-development}" != 'development' ]]; then
  echo 'Refusing to seed outside RAILS_ENV=development' >&2; exit 3
fi
cd "$APP_DIR"
run() {
  local name="$1"; shift
  local started code
  started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "[$started] $name: $*" | tee "$EVIDENCE/$name.command.txt"
  set +e
  "$@" >"$EVIDENCE/$name.stdout.log" 2>"$EVIDENCE/$name.stderr.log"
  code=$?
  set -e
  printf '{"command_name":"%s","started_utc":"%s","exit_code":%s}\n' "$name" "$started" "$code" > "$EVIDENCE/$name.result.json"
  echo "[$name] exit=$code"; [[ "$code" -eq 0 ]]
}
run 00_versions ruby -v
run 01_rails_version bin/rails --version
run 02_database_prepare bin/rails db:create db:migrate
run 03_pure_ruby_tests ruby test/policy_rules_test.rb
run 04_seed_initial bin/rails runner db/seeds/m1_full_business_records.rb
run 05_verify_initial bin/rails runner script/verify_m1_database.rb
run 06_seed_idempotency bin/rails runner db/seeds/m1_full_business_records.rb
run 07_verify_idempotency bin/rails runner script/verify_m1_database.rb
python3 - "$EVIDENCE" <<'PY'
import json,hashlib,sys
from pathlib import Path
p=Path(sys.argv[1]); files=sorted(f for f in p.rglob('*') if f.is_file() and f.name!='checksums.sha256')
(p/'checksums.sha256').write_text(''.join(f'{hashlib.sha256(f.read_bytes()).hexdigest()}  {f.relative_to(p)}\n' for f in files))
print('M1 Rails/PostgreSQL run passed. Evidence:',p)
PY
