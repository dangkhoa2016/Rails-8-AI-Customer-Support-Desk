#!/usr/bin/env bash
# Non-destructive source + HTTP/semantic test checkpoint for synthetic Colab only.
set -Eeuo pipefail
[[ "${M1_SYNTHETIC_DEMO:-}" == YES && "${RAILS_ENV:-development}" == development ]] || { echo 'Synthetic development environment required' >&2; exit 3; }
cd "$(dirname "$0")/.."
OUT="${1:-$PWD/evidence-m2-editorial-semantic-20261029}"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
run() {
  local name="$1"; shift
  date -u +%FT%TZ > "$OUT/$name.start_utc.txt"
  printf '%q ' "$@" > "$OUT/$name.command.txt"; echo >> "$OUT/$name.command.txt"
  local exit_code=0
  "$@" > "$OUT/$name.stdout.log" 2> "$OUT/$name.stderr.log" || exit_code=$?
  echo "$exit_code" > "$OUT/$name.exit_code.txt"
  date -u +%FT%TZ > "$OUT/$name.end_utc.txt"
  echo "$name exit=$exit_code"
  [[ "$exit_code" == 0 ]]
}
run 01_editorial_triage python3 script/m2_editorial_triage.py
run 02_m1_regression env RAILS_ENV=test bin/rails test test/integration/support_desk_security_test.rb
run 03_m2_editorial_security env RAILS_ENV=test bin/rails test test/integration/knowledge_base_security_test.rb
run 04_m2_semantic_security env RAILS_ENV=test bin/rails test test/integration/semantic_kb_security_test.rb
run 05_modal_source_compile python3 -m py_compile modal_app/qwen3_embedding_service.py
run 06_dry_run env KB_ORGANIZATION_SLUG=teamflow-cloud bin/rails runner script/m2_embed_approved.rb
python3 - "$OUT" <<'PY'
import datetime,hashlib,json,sys
from pathlib import Path
out=Path(sys.argv[1]); root=Path.cwd()
steps=sorted(out.glob('*.exit_code.txt'))
codes={p.name.removesuffix('.exit_code.txt'):int(p.read_text()) for p in steps}
source=['app/services/knowledge_semantic_retrieval.rb','app/services/knowledge_embedding_ingestion.rb','app/services/modal_embedding_client.rb','app/services/knowledge_publication.rb','app/models/knowledge_chunk_embedding.rb','db/migrate/20261029010000_create_knowledge_chunk_embeddings.rb','modal_app/qwen3_embedding_service.py','script/m2_editorial_triage.py','script/m2_embed_approved.rb','data/m2/knowledge_drafts.json']
manifest={'status':'PASS_OFFLINE_AND_RAILS_TESTS_ONLY' if len(codes)==6 and all(not x for x in codes.values()) else 'FAIL', 'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'command_exit_codes':codes,'source_sha256':{p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in source},'human_editorial_approved':0,'actual_model_embeddings':0,'modal_gpu_benchmark':'NOT_RUN','pgvector_semantic_tests':'SYNTHETIC_VECTORS_ONLY','m3':'NOT_STARTED'}
(out/'acceptance.json').write_text(json.dumps(manifest,indent=2)+'\n')
files=sorted(p for p in out.iterdir() if p.is_file() and p.name!='checksums.sha256')
(out/'checksums.sha256').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n' for p in files))
print(json.dumps(manifest,indent=2))
PY
(cd "$OUT" && sha256sum -c checksums.sha256 | tail -3)
