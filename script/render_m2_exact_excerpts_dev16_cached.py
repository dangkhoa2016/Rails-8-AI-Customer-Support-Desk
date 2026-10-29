#!/usr/bin/env python3
"""Standalone offline dev16 report including unmodified raw Qwen outputs and rejects."""
import hashlib,json
from pathlib import Path
from html import escape
ROOT=Path(__file__).resolve().parents[1]
E=ROOT/"evidence-m2-exact-excerpts-dev16-cached-20261029"
M=json.loads((ROOT/"review/m2_exact_excerpt_development16_20261029.json").read_text())
R=json.loads((E/"exact-excerpt-live.json").read_text())
A=json.loads((E/"dev16-evaluation.json").read_text())
source={x['id']:x for x in M['cases']}
assessed={x['id']:x for x in A['cases']}
def esc(x):return escape(str(x),quote=True)
cards=[]
for c in R['cases']:
    id=c['id']; orig=source[id]; a=assessed[id]
    state="PASS" if a['fully_mapped_without_unresolved'] else "REVIEW / ABSTAIN"
    color="good" if a['fully_mapped_without_unresolved'] else "bad"
    recovered=a['recovered']
    if recovered:
        spans="".join(f"<li><strong>{esc(x['id'])}</strong> [{x['source_start']}:{x['source_end']}] {esc(x['source_excerpt'])}</li>"
         for x in recovered['claims'])
        unresolved="".join(f"<li>Unresolved [{x['source_start']}:{x['source_end']}]: {esc(x['source_excerpt'])}</li>"
          for x in recovered['unresolved'])
    else:
        spans="<li>No integrity-qualified source spans</li>";unresolved=""
    cards.append(f'''<article class="case" data-tenant="{esc(c['tenant'])}" data-locale="{esc(c['locale'])}">
<header><code>{esc(id)}</code><span>{esc(c['tenant'])}/{esc(c['locale'])}</span><b class="{color}">{esc(state)}</b></header>
<p><strong>Original:</strong> {esc(orig['question'])}</p>
<p class="meta">JSON {esc(c['parse_status'])}; integrity={a['exact_source_spans_pass']};
minimum-intents={a['minimum_intents_recovered']}; no unresolved={a['fully_mapped_without_unresolved']};
reason={esc(a['exact_source_failure'] or '—')}; GPU generation {esc(c['generation_seconds'])}s.</p>
<strong>Deterministically reconstructed segments:</strong><ul>{spans}{unresolved}</ul>
<details><summary>Raw model JSON/text, unmodified</summary><pre>{esc(c['raw'])}</pre></details></article>''')
out=E/"dev16-static-review.html"
assert not out.exists()
s=f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>M2 exact excerpts — synthetic dev16 review</title><style>
:root{{color-scheme:dark;font-family:system-ui,sans-serif}}body{{background:#091523;color:#eaf3ff;margin:0}}
main{{max-width:1080px;margin:0 auto;padding:30px 18px}}h1{{font-size:clamp(1.5rem,3vw,2.4rem)}}
p{{line-height:1.55}}.notice{{border:1px solid #98743a;border-radius:11px;padding:14px 20px;background:#382b18;margin:20px 0}}
.stats{{display:flex;gap:13px;flex-wrap:wrap}}.stat{{border:1px solid #466583;background:#13283e;padding:17px;border-radius:11px;min-width:140px}}.stat b{{font-size:1.5rem;display:block}}
.case{{border:1px solid #385a7e;border-radius:13px;padding:20px;margin:18px 0;background:#122941}}
.case header{{display:flex;justify-content:space-between;gap:12px;flex-wrap:wrap}}
.good{{color:#7ee3b7}}.bad{{color:#ffc0ad}}.meta,small{{color:#b0c5e0}}
pre{{white-space:pre-wrap;overflow-wrap:anywhere;background:#081829;padding:15px;border-radius:8px}}
code{{overflow-wrap:anywhere}}details{{margin-top:20px}}
</style></head><body><main>
<p class="meta">Rails 8 AI Customer Support Desk / M2 synthetic dev / Oct 29, 2026</p>
<h1>Exact excerpt selection — deterministic span recovery</h1>
<div class="notice"><b>Development-only, NOT_RELEASE.</b> These are new developer-written prompts, not human-adjudicated holdout cases. Integrity of exact source spans does not establish correct intent semantics or authorize business actions. Outputs are not automatically used by Rails.</div>
<div class="stats"><div class="stat">Questions<b>{A['questions']}</b></div>
<div class="stat">Valid JSON objects<b>{A['json_object_parsed']}</b></div>
<div class="stat">Exact source integrity<b>{A['source_integrity_valid']}</b></div>
<div class="stat">Min. intents recovered<b>{A['developer_minimum_intents_recovered']}</b></div>
<div class="stat">Full mapping / no unresolved<b>{A['fully_mapped_without_unresolved']}</b></div></div>
<p>Model: <code>{esc(R['model_id'])}@{esc(R['model_revision'])}</code>. GPU: {esc(R['gpu'])}; seed {R['seed']}; elapsed {esc(R['wall_seconds'])} seconds.</p>
<h2>All 16 cases — including rejects</h2>{''.join(cards)}
<h2>Provenance</h2><p>Frozen input SHA256: <code>{esc(A['manifest_sha256'])}</code></p>
<p>Raw Modal inference SHA256: <code>{esc(A['raw_gpu_sha256'])}</code></p>
<p>This self-contained static HTML has no network requests, login, scripts, customer data or writes.</p>
</main></body></html>'''
out.write_text(s)
print(json.dumps({'kind':'SELF_CONTAINED_OFFLINE_DEV16','bytes':out.stat().st_size,'cases':len(cards),'sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'output':str(out)}))
