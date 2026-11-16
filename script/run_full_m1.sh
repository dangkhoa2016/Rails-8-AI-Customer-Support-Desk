#!/usr/bin/env bash
# Full runtime acceptance for disposable PostgreSQL-backed Rails 8 demo.
# NON-DESTRUCTIVE: no db:drop, no db:reset; refuses production/real customer databases.
set -Eeuo pipefail
[[ "${M1_SYNTHETIC_DEMO:-}" == YES ]] || { echo 'Set M1_SYNTHETIC_DEMO=YES for synthetic DB only.' >&2; exit 3; }
[[ "${RAILS_ENV:-development}" == development ]] || { echo 'Set RAILS_ENV=development' >&2; exit 3; }
cd "$(dirname "$0")/.."
OUTPUT="${1:-$PWD/evidence-run}"
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"
run() {
  local title="$1"; shift
  local started finished code
  started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '%q ' "$@" > "$OUTPUT/$title.command.txt"; printf '\n' >> "$OUTPUT/$title.command.txt"
  set +e
  "$@" >"$OUTPUT/$title.stdout.log" 2>"$OUTPUT/$title.stderr.log"
  code=$?
  set -e
  finished="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"start_utc":"%s","end_utc":"%s","exit_code":%d}\n' "$started" "$finished" "$code" > "$OUTPUT/$title.result.json"
  echo "$title: $code"
  [[ "$code" -eq 0 ]]
}
run 00_ruby_version ruby --version
run 01_rails_version bin/rails --version
run 02_blueprint python3 script/validate_approved_blueprint.py
run 03_offline_dataset python3 script/verify_m1_dataset.py --blueprint data/policy/canonical_blueprint.json --dataset data/m1_business_records.json --report "$OUTPUT/offline-relational-report.json"
run 04_policy_tests ruby test/policy_rules_test.rb
run 05_db_create bin/rails db:create
run 06_db_migrate bin/rails db:migrate
run 07_seed_first bin/rails runner db/seeds/m1_full_business_records.rb
run 08_verify_first bin/rails runner script/verify_m1_database.rb
run 09_seed_second bin/rails runner db/seeds/m1_full_business_records.rb
run 10_verify_second bin/rails runner script/verify_m1_database.rb
# Test DB already provisioned for vector via privileged extension preflight.
# Use non-destructive migrations; db:test:prepare would reload structure as unprivileged role.
run 11_db_test_prepare env RAILS_ENV=test bin/rails db:migrate
run 12_http_security env RAILS_ENV=test bin/rails test test/integration/support_desk_security_test.rb
run 13_routes bin/rails routes
python3 - "$OUTPUT" <<'PY'
import sys,hashlib,json,datetime
from pathlib import Path
p=Path(sys.argv[1]); names=['00_ruby_version','01_rails_version','02_blueprint','03_offline_dataset','04_policy_tests','05_db_create','06_db_migrate','07_seed_first','08_verify_first','09_seed_second','10_verify_second','11_db_test_prepare','12_http_security','13_routes']
rows={n:json.loads((p/f'{n}.result.json').read_text()) for n in names}
result={'status':'PASS_RUNTIME_ACCEPTANCE' if all(r['exit_code']==0 for r in rows.values()) else 'FAIL','environment':'Rails 8 development / PostgreSQL','checked_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'commands':rows,'modal_inference':'NOT_RUN','kb_full_text':'NOT_STARTED'}
(p/'acceptance-summary.json').write_text(json.dumps(result,indent=2)+'\n')
files=sorted(q for q in p.rglob('*') if q.is_file() and q.name != 'checksums.sha256')
(p/'checksums.sha256').write_text(''.join(hashlib.sha256(f.read_bytes()).hexdigest+'  '+str(f.relative_to(p))+'\n' for f in files))
print(json.dumps(result,indent=2))
PY
