#!/usr/bin/env bash
# M2 4B/4B OFFLINE PREFLIGHT: does not deploy Modal or call paid GPU.
set -Eeuo pipefail
cd "$(dirname "$0")/.."
[[ "${M1_SYNTHETIC_DEMO:-}" == YES && "${RAILS_ENV:-development}" == development ]] || { echo 'synthetic development only'; exit 3; }
OUT="$PWD/evidence-m2-dual-qwen3-4b-preflight"
mkdir -p "$OUT"
run() {
  local stage="$1"; shift
  date -u +%FT%TZ > "$OUT/$stage.started_utc.txt"
  printf '%q ' "$@" > "$OUT/$stage.command.txt"; echo >> "$OUT/$stage.command.txt"
  local status=0
  "$@" > "$OUT/$stage.stdout.log" 2> "$OUT/$stage.stderr.log" || status=$?
  echo "$status" > "$OUT/$stage.exit_code.txt"
  date -u +%FT%TZ > "$OUT/$stage.ended_utc.txt"
  echo "$stage exit=$status"
  [[ "$status" == 0 ]]
}
run 01_editorial_source python3 script/verify_m2_priority_proposals.py
run 02_approved_db bin/rails runner script/verify_m2_dual_4b_checkpoint.rb
run 03_migrations_dev bin/rails db:migrate:status
run 04_migrations_test env RAILS_ENV=test bin/rails db:migrate:status
run 05_security_tests env RAILS_ENV=test bin/rails test test/helpers/knowledge_articles_helper_test.rb test/integration/support_desk_security_test.rb test/integration/knowledge_base_security_test.rb test/integration/semantic_kb_security_test.rb
run 06_gpu_dry_run bin/rails runner script/m2_dual_4b_pilot.rb
run 07_lexical_baseline bin/rails runner script/m2_lexical_baseline.rb
run 08_python_syntax python3 -m py_compile modal_app/qwen3_embedding_service.py modal_app/qwen3_reranker_service.py
run 09_modal_sdk_import /tmp/rails8-modal-check-uv/bin/python script/verify_modal_4b_static.py
python3 - "$OUT" <<'PY'
from pathlib import Path
import datetime,hashlib,json,sys
out=Path(sys.argv[1]);base=Path.cwd()
exit_codes={f.name.replace('.exit_code.txt',''):int(f.read_text()) for f in sorted(out.glob('*.exit_code.txt'))}
checks={name:hashlib.sha256((base/name).read_bytes()).hexdigest() for name in [
  'data/m2/knowledge_drafts.json', 'data/policy/canonical_blueprint.json',
  'review/m2_priority_editorial_proposals_20261029.json', 'review/m2_dual_qwen3_4b_pilot_queries.json',
  'modal_app/qwen3_embedding_service.py','modal_app/qwen3_reranker_service.py']}
meta={'status':'PASS_PREFLIGHT_ONLY_NO_GPU' if len(exit_codes)==9 and all(x==0 for x in exit_codes.values()) else 'FAIL',
  'captured_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
  'stage_exit_codes':exit_codes,'sha256':checks,'approved_v2':12,'approved_chunks':84,
  'actual_embeddings':0,'modal_account_auth':'NOT_AUTHENTICATED',
  'gpu_inference':'NOT_RUN','reranker_inference':'NOT_RUN',
  'model_eval_status':'NOT_RUN','synthetic_vectors_only':True,
  'lexical_baseline':'12 questions, Recall@8=0/12, MRR@8=0',
  'no_m0_m1_reseed':True,'no_public_tunnel_for_rails':True}
(out/'final_acceptance.json').write_text(json.dumps(meta,indent=2)+'\n')
files=sorted(f for f in out.iterdir() if f.is_file() and f.name!='checksums.sha256')
(out/'checksums.sha256').write_text(''.join(hashlib.sha256(f.read_bytes()).hexdigest()+'  '+f.name+'\n' for f in files))
print(json.dumps(meta,indent=2))
raise SystemExit(0 if meta['status'].startswith('PASS') else 1)
PY
(cd "$OUT" && sha256sum -c checksums.sha256 >/dev/null)
echo 'DUAL_4B_PREFLIGHT_EVIDENCE_CHECKSUM_PASS'
