#!/usr/bin/env python3
"""Read-only, self-contained HTML audit of frozen, real Modal POC outputs."""
import hashlib,json
from pathlib import Path
from html import escape
ROOT=Path(__file__).resolve().parents[1]
EV=ROOT/"evidence-m2-new-modal-model-poc-20261029"
REPORT=json.loads((EV/"poc-evaluation.json").read_text())
MAN=json.loads((ROOT/"review/m2_new_models_isolated_poc_development_20261029.json").read_text())
D=json.loads((EV/"decomposition-live.json").read_text())
N=json.loads((EV/"nli-live.json").read_text())
case_map={a["id"]:a for a in MAN["decomposition_cases"]}
evaluation={x["id"]:x for x in REPORT["decomposition"]["cases"]}
nf={x["id"]:x for x in REPORT["nli"]["cases"]}
assert len(D["results"])==8 and len(N["results"])==12
def e(x):return escape(str(x),quote=True)
dparts=[]
for case in D["results"]:
    source=case_map[case["id"]]
    ev=evaluation[case["id"]]
    state="PASS" if ev["schema_source_spans_valid"] else "BLOCKED"
    dparts.append(f'''<article class="case"><div class="meta"><code>{e(case['id'])}</code><span>{e(source['tenant'])} / {e(source['locale'].upper())}</span><b>{state}</b></div>
<p><strong>Original question:</strong> {e(source['question'])}</p>
<p class="sub">JSON: {e(case['parse_status'])} · Schema/source: {e(ev['failure_reason'] or 'PASS')} · Generation: {e(case['generation_seconds'])} s</p>
<details><summary>Exact raw model output (not repaired)</summary><pre>{e(case['raw_model_output'])}</pre></details></article>''')
nparts=[]
for case in N["results"]:
    gold=nf[case["id"]]
    passed=gold["matches_developer_label"]
    status="MATCH" if passed else "MISMATCH"
    sc=" · ".join(f"{e(k)} {v:.3f}" for k,v in case["scores"].items())
    nparts.append(f'''<tr><td><code>{e(case['id'])}</code><small>{e(case['tenant'])}/{e(case['locale'])}</small></td>
<td>{e(case['article_key'])}</td><td>{e(gold['developer_label'])}</td>
<td>{e(case['predicted_label'])}</td><td><strong>{status}</strong></td>
<td>{sc}</td></tr>''')
f=EV/"poc-review-static.html"
assert not f.exists()
body=f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>M2 isolated Modal models — GPU evidence</title><style>
:root{{color-scheme:dark;font-family:system-ui,sans-serif}}body{{margin:0;background:#071526;color:#eef5ff}}main{{max-width:1120px;margin:auto;padding:30px 20px}}
h1{{font-size:clamp(1.6rem,3vw,2.2rem)}}h2{{margin-top:40px}}.sub,small{{color:#afc4df}}
.banner{{padding:14px 18px;background:#31291d;border:1px solid #c39d55;border-radius:10px}}
.summary{{display:flex;gap:15px;flex-wrap:wrap;margin:22px 0}}.stat{{background:#142940;border:1px solid #476585;padding:16px;border-radius:11px;min-width:150px}}
.stat b{{display:block;font-size:1.5rem}}article.case{{background:#11263e;border:1px solid #385978;border-radius:12px;padding:20px;margin:16px 0}}
.meta{{display:flex;gap:18px;justify-content:space-between;flex-wrap:wrap}}.meta b{{color:#ffbcbc}}p{{line-height:1.6}}
details{{margin-top:10px}}pre{{white-space:pre-wrap;overflow-wrap:anywhere;background:#07172a;padding:16px;border-radius:8px}}
table{{width:100%;border-collapse:collapse;font-size:.91rem}}td,th{{padding:12px;border-bottom:1px solid #355574;text-align:left;vertical-align:top}}td small{{display:block}}
.tablewrap{{overflow-x:auto}}code{{overflow-wrap:anywhere}}
</style></head><body><main>
<p class="sub">Rails 8 AI Customer Support Desk · October 29, 2026 · synthetic development only</p>
<h1>Isolated Modal GPU model POC</h1>
<div class="banner"><strong>NO RELEASE.</strong> Developer-authored inputs. No independent human sign-off, no customer data, no business writes, no model endpoint integration.
All raw outputs are shown unmodified. Scores are uncalibrated.</div>
<div class="summary">
<div class="stat">Qwen JSON parsed<b>7 / 8</b></div>
<div class="stat">Qwen valid source spans<b>0 / 8</b></div>
<div class="stat">NLI source integrity<b>12 / 12</b></div>
<div class="stat">NLI matched dev labels<b>9 / 12</b></div>
<div class="stat">GPU job wall time<b>123.3 s</b></div>
</div>
<h2>Qwen3-4B-Instruct-2507 — manual questions, model-generated claims</h2>
<p class="sub">Pinned SHA {e(D['model_revision'])}. GPU {e(D['gpu'])}; GPU allocated {D['gpu_peak_allocated_bytes']/1024**3:.2f} GiB peak. 7/8 parsed JSON but none meets exact source-span integrity; NO silent repair.</p>
{''.join(dparts)}
<h2>mDeBERTa-v3-base-mnli-xnli — policy NLI</h2>
<p class="sub">Pinned SHA {e(N['model_revision'])}. GPU {e(N['gpu'])}, float32; GPU allocated {N['gpu_peak_allocated_bytes']/1024**3:.2f} GiB peak. Developer labels are not independently verified.</p>
<div class="tablewrap"><table><thead><tr><th>Case</th><th>Approved KB</th><th>Developer label</th><th>Predicted</th><th>Match</th><th>Raw softmax by label</th></tr></thead><tbody>{''.join(nparts)}</tbody></table></div>
<h2>Provenance and constraints</h2><p>Frozen manifest SHA256: <code>{e(REPORT['manifest_sha256'])}</code></p>
<p>Exact NLI premise SHA256: <code>{e(REPORT['premises_sha256'])}</code></p>
<p>Inference evidence Qwen SHA256: <code>{e(REPORT['decomposition']['raw_results_sha256'])}</code></p>
<p>Inference evidence mDeBERTa SHA256: <code>{e(REPORT['nli']['raw_results_sha256'])}</code></p>
<p class="sub">Static file with no API calls, external fonts, images, scripts or backend actions. This is a preliminary technical feasibility study, not an entailment acceptance test.</p>
</main></body></html>'''
f.write_text(body)
print(json.dumps({'status':'STATIC_HTML_PASS','path':str(f),'bytes':f.stat().st_size,
    'sha256':hashlib.sha256(f.read_bytes()).hexdigest(),
    'question_cards':body.count('<article class="case">'),
    'nli_rows':body.count('<tr>')-1},indent=2))
