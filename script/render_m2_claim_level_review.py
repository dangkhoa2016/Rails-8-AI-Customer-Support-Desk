#!/usr/bin/env python3
"""Render an offline, read-only synthetic claim-evidence review page.
No network calls, no PII, no scripts, no proxy tokens, no business writes.
All model citations are proposals requiring human review."""
from pathlib import Path
from html import escape
from collections import Counter
import json,hashlib

root=Path(__file__).resolve().parents[1]
ev=root/'evidence-m2-claim32x2-20261029'
manifest=root/'review/m2_claim_level_manual32x2_lockbox_20261029.json'
rows=json.loads(manifest.read_text())['cases']
results=[json.loads(x) for x in (ev/'claim32x2-live.jsonl').read_text().splitlines()]
report=json.loads((ev/'claim32x2-report.json').read_text())
assert len(rows)==32 and len(results)==32
assert report['results_sha256']==hashlib.sha256((ev/'claim32x2-live.jsonl').read_bytes()).hexdigest()
lookup={r['id']:r for r in results}
def e(x):return escape(str(x),quote=True)
cards=[]
for source in rows:
    outcome=lookup[source['id']]
    claim_rows=[]
    for original,observed in zip(source['claims'],outcome['claims']):
        assert original['claim_id']==observed['claim_id']
        gold='KB supports the policy claim' if original['gold_article_key'] else 'Outside approved KB'
        evidence='Evidence candidate — human must check' if observed['candidate'] else 'No qualified citation'
        if observed['candidate'] and not original['gold_article_key']: verdict='False positive'
        elif original['gold_article_key'] and not observed['candidate_correct']: verdict='False abstention'
        elif observed['candidate_correct']: verdict='Correct candidate'
        else: verdict='Correct abstention'
        cite=', '.join(e(x['citation']) for x in observed['citations']) or '—'
        claim_rows.append(f'''<div class="claim"><p class="question">{e(original['text'])}</p>
        <p><b>Gold:</b> {e(gold)} · <b>Model:</b> {e(evidence)} · <strong>{e(verdict)}</strong></p>
        <div class="citation"><b>Citations:</b> {cite}</div></div>''')
    cards.append(f'''<article class="case" data-tenant="{e(source['tenant'])}" data-locale="{e(source['locale'])}">
    <header><code>{e(source['id'])}</code><span>{e(source['tenant'])} · {e(source['locale'].upper())}</span>
    <span>{e(outcome['decomposed_candidate_state'])}</span></header>
    <h3>{e(source['question'])}</h3>{''.join(claim_rows)}</article>''')
text=f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Rails 8 Support Desk — claim-level synthetic evidence review</title>
<style>
:root{{color-scheme:dark;font-family:system-ui,sans-serif}}body{{margin:0;background:#0a1320;color:#e8efff}}main{{max-width:1100px;margin:0 auto;padding:32px 20px}}
h1{{font-size:clamp(1.5rem,3vw,2.4rem)}}.muted{{color:#aab9d4}}.controls{{display:flex;gap:15px;flex-wrap:wrap;margin:22px 0}}
label{{font-weight:600}}select{{background:#14263c;color:white;border:1px solid #526a88;border-radius:8px;padding:10px;min-width:165px}}
.stats{{display:flex;gap:16px;flex-wrap:wrap}}.stat{{background:#122238;padding:16px;border:1px solid #38516f;border-radius:12px;min-width:155px}}
.stat b{{display:block;font-size:1.6rem;margin:4px 0}}.case{{padding:22px;margin:16px 0;background:#122036;border:1px solid #39506a;border-radius:12px}}
.case header{{display:flex;justify-content:space-between;flex-wrap:wrap;gap:10px;color:#a9c2e3}}.case h3{{font-size:1.1rem;line-height:1.5}}
.claim{{background:#172c46;padding:14px 18px;border-radius:9px;margin:10px 0}}.question{{font-size:1.03rem;line-height:1.5}}
.citation{{overflow-wrap:anywhere;font-size:.88rem;color:#b4c9e2}}.alert{{padding:13px 16px;border:1px solid #7f6940;background:#382c16;border-radius:9px;margin:18px 0}}
code{{overflow-wrap:anywhere}}.case[hidden]{{display:none}}a{{color:#9dc5ff}}
</style></head><body><main>
<p class="muted">Synthetic experiment · M2 · Not production</p><h1>Atomic claim × approved KB evidence</h1>
<p class="muted">32 manually decomposed questions / 64 atomic policy claims. Embedding-4B + Reranker-4B, pinned on Modal. Gold labels were developer-authored before inference, not independently adjudicated.</p>
<p class="alert"><strong>Human approval mandatory.</strong> Reranker scores and probe comparisons are not proof of entailment. No autonomous answer, refund, shipment change, plan activation, or customer action is authorized by this page.</p>
<section class="stats"><div class="stat">Supported claims<b>{report['atomic_claim_retrieval']['tp']+report['atomic_claim_retrieval']['fn']}</b></div>
<div class="stat">Correct candidates<b>{report['atomic_claim_retrieval']['tp']}</b></div>
<div class="stat">False candidates<b>{report['atomic_claim_retrieval']['fp']}</b></div>
<div class="stat">False abstentions<b>{report['atomic_claim_retrieval']['fn']}</b></div>
<div class="stat">Embedding calls<b>{report['inference_calls']['embedding']}</b></div><div class="stat">Rerank calls<b>{report['inference_calls']['reranker']}</b></div></section>
<div class="controls"><label>Tenant <select id="tenant"><option value="">Both organizations</option><option value="teamflow-cloud">TeamFlow Cloud</option><option value="novamart-store">NovaMart Store</option></select></label>
<label>Language <select id="locale"><option value="">Both languages</option><option value="vi">Vietnamese</option><option value="en">English</option></select></label></div>
<p id="count" class="muted"></p><section id="cases">{''.join(cards)}</section>
<hr><p class="muted">No network requests, no credentials or backend mutations. Manifest SHA256: {e(report['manifest_sha256'])}. Evidence SHA256: {e(report['results_sha256'])}.</p>
</main><script>
const filters=[document.getElementById('tenant'),document.getElementById('locale')];
function update(){{let visible=0;document.querySelectorAll('.case').forEach(x=>{{const show=(!filters[0].value||x.dataset.tenant===filters[0].value)&&(!filters[1].value||x.dataset.locale===filters[1].value);x.hidden=!show;if(show)visible++;}});document.getElementById('count').textContent=visible+' / 32 cases';}}
filters.forEach(x=>x.addEventListener('change',update));update();
</script></body></html>'''
path=ev/'claim-level-review.html'
assert not path.exists()
path.write_text(text)
print(json.dumps({'html_file':str(path),'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'cases':len(cards)}))
