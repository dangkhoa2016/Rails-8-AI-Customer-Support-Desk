#!/usr/bin/env bash
# M2 integration acceptance on a disposable Rails 8 + PostgreSQL database.
# Run M1 first; this script never drops/resets databases or publishes KB automatically.
set -Eeuo pipefail
[[ "${M1_SYNTHETIC_DEMO:-}" == YES ]] || { echo 'Set M1_SYNTHETIC_DEMO=YES for synthetic DB only.' >&2; exit 3; }
[[ "${RAILS_ENV:-development}" == development ]] || { echo 'Only development mode allowed.' >&2; exit 3; }
cd "$(dirname "$0")/.."
OUT="${1:-$PWD/evidence-m2-runtime}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
run() {
  local step="$1"; shift
  date -u +%FT%TZ > "$OUT/$step.start_utc.txt"
  printf '%q ' "$@" > "$OUT/$step.command.txt"; printf '\n' >> "$OUT/$step.command.txt"
  set +e
  "$@" > "$OUT/$step.stdout.log" 2> "$OUT/$step.stderr.log"
  local code=$?
  set -e
  date -u +%FT%TZ > "$OUT/$step.end_utc.txt"
  echo "$code" > "$OUT/$step.exit_code.txt"
  echo "$step exit=$code"
  [[ "$code" == 0 ]]
}
run 01_offline_knowledge python3 script/verify_m2_knowledge.py --report "$OUT/offline-knowledge-report.json"
run 02_python_negative_tests python3 -m unittest discover -s test -p test_m2_knowledge.py -v
run 03_rails_version bin/rails --version
run 04_migrate bin/rails db:migrate
run 05_seed_first bin/rails runner db/seeds/m2_knowledge_base.rb
run 06_db_verify_first bin/rails runner script/verify_m2_database.rb
run 07_seed_second bin/rails runner db/seeds/m2_knowledge_base.rb
run 08_db_verify_second bin/rails runner script/verify_m2_database.rb
# Run test migrations without purging a DB that requires privileged pgvector extension.
run 09_test_db_prepare env RAILS_ENV=test bin/rails db:migrate
run 10_http_security env RAILS_ENV=test bin/rails test test/integration/knowledge_base_security_test.rb
run 11_routes bin/rails routes
python3 - "$OUT" <<'PY'
import json,sys,hashlib,datetime
from pathlib import Path
out=Path(sys.argv[1]); codes={p.name[:-14]:int(p.read_text()) for p in out.glob('*.exit_code.txt')}
report={'status':'PASS_RUNTIME_ACCEPTANCE' if len(codes)==11 and all(v==0 for v in codes.values()) else 'FAIL',
        'captured_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'commands':codes,'editorial_approval':'PENDING_HUMAN_REVIEW',
        'embeddings':'NOT_RUN','modal_inference':'NOT_RUN'}
(out/'m2-runtime-summary.json').write_text(json.dumps(report,indent=2)+'\n')
files=sorted(x for x in out.rglob('*') if x.is_file() and x.name!='checksums.sha256')
(out/'checksums.sha256').write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(out)}\n' for p in files))
print(json.dumps(report,indent=2))
PY
