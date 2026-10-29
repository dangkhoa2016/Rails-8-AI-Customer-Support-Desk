#!/usr/bin/env python3
"""Self-contained offline HTML for all 20 synthetic partition-aware development cases."""
import hashlib,json
from html import escape
from pathlib import Path

R=Path(__file__).resolve().parents[1]
E=R/"evidence-m2-partition-host-envelope-dev16-20261029"
m=json.loads((R/"review/m2_partition_host_envelope_fresh_dev16_20261029.json").read_text())
p=json.loads((E/"partitions-frozen-pre-gpu.json").read_text())
g=json.loads((E/"idonly-gpu-live.json").read_text())
a=json.loads((E/"idonly-evaluation.json").read_text())
def esc(x):return escape(str(x),quote=True)
source={x["id"]:x for x in m["cases"]}
eval_by={x["id"]:x for x in a["cases"]}
parts={x["id"]:x for x in p["admitted"]}
answers={x["id"]:x for x in g["results"]}
cards=[]
for case in m["cases"]:
    ident=case["id"]
    ev=eval_by[ident]
    question=case["question"]
    if ident not in parts:
        details=f"<p><strong>Code abstained before GPU:</strong> {esc(ev['pre_gpu_abstain_reason'])}</p>"
        raw=""
    else:
        part=parts[ident]
        units="".join(f"<li><code>{esc(u['id'])}</code> [{u['source_start']}:{u['source_end']}] {esc(u['source_excerpt'])}</li>" for u in part["units"])
        details=(f"<p>Unit assignments: <strong>{'PASS' if ev['one_to_one_integrity_pass'] else 'BLOCKED'}</strong>."
                 f" Expected minimum classified claim units: {case['expected_min_claim_units']}."
                 f" Known untrusted unit IDs (developer): {esc(case['expected_untrusted_unit_ids'])}."
                 f" Reason: {esc(ev.get('failure_reason'))}. Developer-untrusted safety: "
                 f"{esc(ev['known_untrusted_handling_pass'])}.</p>"
                 f"<p><strong>Immutable source units</strong></p><ul>{units}</ul>")
        raw=f"<details><summary>Raw model response (unaltered)</summary><pre>{esc(answers[ident]['raw_output'])}</pre></details>"
    cards.append(f'''<article><header><code>{esc(ident)}</code><span>{esc(case['tenant'])}/{esc(case['locale'].upper())}</span></header>
<p><strong>Source question:</strong> {esc(question)}</p>{details}{raw}</article>''')
out=E/"host-envelope-dev16-review.html"
assert not out.exists()
content=f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>M2 host-owned metadata ID-only development 16</title><style>
:root{{color-scheme:dark;font-family:system-ui,sans-serif}}body{{margin:0;background:#0b1727;color:#e7f2ff}}
main{{max-width:1100px;margin:0 auto;padding:24px}}.warning{{border:1px solid #b58b44;background:#352713;border-radius:8px;padding:16px}}
.summary{{display:flex;flex-wrap:wrap;gap:12px;margin:25px 0}}.metric{{background:#192b41;border:1px solid #446384;border-radius:10px;padding:14px;min-width:120px}}
.metric b{{display:block;font-size:1.5rem}}article{{padding:17px;border:1px solid #496886;background:#14273f;border-radius:11px;margin:18px 0}}
header{{display:flex;justify-content:space-between;gap:12px;flex-wrap:wrap}}p{{line-height:1.5}}
small,header span{{color:#aac7e6}}code,pre{{overflow-wrap:anywhere}}pre{{white-space:pre-wrap;background:#071525;padding:15px;border-radius:8px}}summary{{cursor:pointer}}
</style></head><body><main><small>Rails 8 AI Customer Support Desk · synthetic experimental evidence · October 29, 2026</small>
<h1>Host-owned metadata classifier · development16</h1>
<div class="warning"><strong>NOT RELEASE / NOT HUMAN VERIFIED.</strong> Unit boundaries are made by conservative code, so classification cannot overlap or delete original source. Host-owned schema and source hash are never accepted from the model. A valid assignment does not certify semantic correctness, claims safety, policy entailment or permission to perform actions. All raw fails preserved.</div>
<div class="summary">
<div class="metric">Total cases<b>{a['total_development_cases']}</b></div>
<div class="metric">Pre-GPU abstains<b>{a['pre_gpu_abstained']}</b></div>
<div class="metric">GPU-run cases<b>{a['gpu_executed']}</b></div>
<div class="metric">Strict label schema<b>{a['strict_id_only_contract_pass']}</b></div>
<div class="metric">Full, no unresolved<b>{a['full_no_unresolved_with_minimum_pass']}</b></div>
</div>
<h2>All source questions and unmodified outcomes</h2>
{''.join(cards)}
<h2>Provenance</h2>
<p>Model revision: <code>{esc(g['model_revision'])}</code>. GPU: {esc(g['gpu'])}; source: {esc(g['model_source'])}; seed: {g['seed']}.</p>
<p>Frozen manifest SHA256: <code>{esc(a['manifest_sha256'])}</code></p>
<p>Frozen pre-GPU partitions SHA256: <code>{esc(a['pre_gpu_partitions_sha256'])}</code></p>
<p>Unmodified GPU output SHA256: <code>{esc(a['raw_gpu_sha256'])}</code></p>
<p>Offline static HTML; no scripts, network dependencies, customer credentials, business writes or API endpoints.</p>
</main></body></html>'''
out.write_text(content)
assert content.count("<article>")==16 and "<script" not in content
print(json.dumps({"status":"STATIC_HTML_PASS","cases":16,"bytes":out.stat().st_size,
  "sha256":hashlib.sha256(out.read_bytes()).hexdigest()},indent=2))
