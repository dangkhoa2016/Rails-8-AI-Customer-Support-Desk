#!/usr/bin/env bash
# Read-only checks, except Rails tests writing solely to test DB.
set -Eeuo pipefail
[[ "${M1_SYNTHETIC_DEMO:-}" == YES && "${RAILS_ENV:-development}" == development ]] || { echo 'Synthetic development mode required' >&2; exit 3; }
cd "$(dirname "$0")/.."
OUT="$PWD/evidence-m2-priority-20261029"
mkdir -p "$OUT"
run() {
  local stage="$1"; shift
  date -u +%FT%TZ > "$OUT/$stage.started_utc.txt"
  printf '%q ' "$@" > "$OUT/$stage.command.txt"; echo >> "$OUT/$stage.command.txt"
  set +e
  "$@" > "$OUT/$stage.stdout.log" 2> "$OUT/$stage.stderr.log"
  local status=$?
  set -e
  echo "$status" > "$OUT/$stage.exit_code.txt"
  date -u +%FT%TZ > "$OUT/$stage.ended_utc.txt"
  echo "$stage exit=$status"
  [[ "$status" == 0 ]]
}
run 01_v2_offline python3 script/verify_m2_priority_proposals.py
run 02_v2_database bin/rails runner script/verify_m2_priority_database.rb
run 03_regression env RAILS_ENV=test bin/rails test test/integration/support_desk_security_test.rb test/integration/knowledge_base_security_test.rb test/integration/semantic_kb_security_test.rb
run 04_preview python3 script/build_m2_priority_preview.py
run 05_ui_routes bin/rails routes
python3 - "$OUT" <<'PY'
import sys,json,hashlib,datetime
from pathlib import Path
out=Path(sys.argv[1]); root=Path.cwd()
codes={f.name.removesuffix('.exit_code.txt'):int(f.read_text()) for f in sorted(out.glob('*.exit_code.txt'))}
checks={f:hashlib.sha256((root/f).read_bytes()).hexdigest() for f in [
  'data/m2/knowledge_drafts.json',
  'data/policy/canonical_blueprint.json',
  'review/m2_priority_editorial_proposals_20261029.json',
  'preview/m2_priority_editorial/index.html',
]}
state={'status':'PASS_SOURCE_DB_AND_TESTS_ONLY' if len(codes)==5 and all(v==0 for v in codes.values()) else 'FAIL',
  'captured_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
  'stages_exit_codes':codes,'source_sha256':checks,
  'editorial':'12_V2_DRAFTS_PENDING_HUMAN_APPROVAL','human_approved_versions':0,
  'modal_model_execution':'NOT_RUN','real_embeddings':0,
  'security_tests':'TEST_DB_WITH_SYNTHETIC_VECTORS','public_deployment':'NOT_RUN'}
(out/'final_acceptance.json').write_text(json.dumps(state,indent=2)+'\n')
files=sorted(f for f in out.glob('*') if f.is_file() and f.name!='checksums.sha256')
(out/'checksums.sha256').write_text(''.join(hashlib.sha256(f.read_bytes()).hexdigest()+'  '+f.name+'\n' for f in files))
print(json.dumps(state,indent=2))
PY
(cd "$OUT" && sha256sum -c checksums.sha256 >/dev/null)
echo 'FINAL_CHECKSUMS_PASS'
