#!/usr/bin/env python3
"""Standalone synthetic-KB reviewer workbook, BLIND to gold and assistant labels.
No external requests, analytics, cookies, backend writes or model inference.
Reviewer must export their own local JSON; this does not certify independence.
"""
from pathlib import Path
from html import escape
import json,hashlib
ROOT=Path(__file__).resolve().parents[1]
QUEUE=ROOT/'evidence-m2-claim32x2-20261029/claim-level-blind-human-validation.json'
SNAP=ROOT/'evidence-m2-claim64-provisional-audit-20261029/approved-kb-v2-readonly-snapshot.json'
OUT=ROOT/'evidence-m2-claim64-provisional-audit-20261029/independent-reviewer-workbook.html'
assert not OUT.exists()
queue=json.loads(QUEUE.read_text())
snap=json.loads(SNAP.read_text())
tasks=queue['tasks']
docs=snap['articles']
assert len(tasks)==64 and len(docs)==12
article_ref={ (x['tenant'],x['locale'],x['article_key']) for x in docs }
def h(x):return escape(str(x),quote=True)
docs_index={(x['tenant'],x['locale']):[] for x in docs}
for x in docs:
    docs_index[(x['tenant'],x['locale'])].append(x)
cards=[]
for idx,task in enumerate(tasks,1):
    id=task['claim_id']
    articles=docs_index[(task['tenant'],task['locale'])]
    opts=''.join(f'<option value="{h(a["article_key"])}">{h(a["article_key"])} / v{a["article_version_number"]}</option>' for a in articles)
    cards.append(f'''<article class="task" data-id="{h(id)}" data-tenant="{h(task['tenant'])}" data-locale="{h(task['locale'])}">
    <header><strong>{h(id)}</strong><small>{h(task['tenant'])} / {h(task['locale'].upper())}</small></header>
    <p><b>Parent question:</b> {h(task['parent_question'])}</p>
    <p class="atomic"><b>Atomic question:</b> {h(task['atomic_claim'])}</p>
    <label>Answerability from approved policy
      <select class="verdict"><option value="">Select only after reading KB</option>
        <option value="affirmative_policy">Affirmative/conditional policy answer</option>
        <option value="explicit_negative_policy">Explicit policy-supported “No”</option>
        <option value="not_documented">Not documented / no safe answer</option>
        <option value="uncertain_needs_second_reviewer">Uncertain — require second reviewer</option>
      </select></label>
    <label>Supporting approved article (if any)
      <select class="article"><option value="">None / not determined</option>{opts}</select>
    </label>
    <label>Exact policy quotation or section (do not fabricate)
      <textarea class="evidence" rows="2" placeholder="Citation/section + short source quotation"></textarea></label>
    <label>Reason and case-specific dependencies
      <textarea class="reason" rows="2" placeholder="Explain ambiguity or required order/workspace verification"></textarea></label>
    </article>''')
details=[]
for x in docs:
    sha=x['body_sha256']
    details.append(f'''<details class="kb"><summary>{h(x['tenant'])} · {h(x['locale'].upper())} · <b>{h(x['article_key'])}</b>
      · approved v{h(x['article_version_number'])} · SHA256 {h(sha[:14])}…</summary>
      <pre>{h(x['body'])}</pre><small>SHA256: <code>{h(sha)}</code></small></details>''')
metadata={'source_manifest_sha256':queue['source_manifest_sha256'],
 'candidate_evidence_sha256':queue['model_evidence_sha256'],
 'approved_snapshot_sha256':hashlib.sha256(SNAP.read_bytes()).hexdigest(),
 'review_status':'DRAFT_UNVERIFIED_REQUIRES_EXTERNAL_HUMAN_SIGNOFF'}
serialized=json.dumps(metadata,ensure_ascii=False).replace('<','\\u003c')
page=f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>M2 - independent reviewer worksheet - synthetic KB</title><style>
:root{{color-scheme:dark;font-family:system-ui,sans-serif}}body{{background:#091424;color:#edf4ff;margin:0}}main{{max-width:1060px;margin:0 auto;padding:30px 18px}}
h1{{font-size:clamp(1.6rem,3vw,2.3rem)}}p{{line-height:1.5}}small,.muted{{color:#b2c7e3}}
.alert{{padding:14px 18px;background:#302719;border:1px solid #987c48;border-radius:9px;margin:20px 0}}
header,.filters{{display:flex;gap:14px;justify-content:space-between;flex-wrap:wrap;align-items:center}}
label{{display:block;font-weight:600;margin:14px 0}}select,input,textarea{{display:block;box-sizing:border-box;width:100%;padding:11px;margin-top:6px;background:#152940;color:#f4f8ff;border:1px solid #5b7999;border-radius:7px;font:inherit}}
.filters label{{flex:1;min-width:175px}}.task{{background:#12263f;border:1px solid #385778;border-radius:12px;padding:20px;margin:16px 0}}
.atomic{{padding:13px;background:#1b3553;border-radius:7px}}button{{padding:12px 18px;border-radius:8px;border:0;background:#9bc2ff;color:#07172c;font-weight:700;cursor:pointer}}
.kb{{padding:14px;background:#14263c;border-radius:9px;margin:12px 0;border:1px solid #385774}}.kb pre{{white-space:pre-wrap;word-break:break-word;line-height:1.5;font-size:.94rem}}
.task[hidden]{{display:none}}code{{overflow-wrap:anywhere}}
</style></head><body><main>
<p class="muted">Rails 8 AI Customer Support Desk · synthetic dataset · 2026-10-29</p>
<h1>Independent human policy-review worksheet</h1>
<p class="alert">Reviewer labels are NOT filled in. This workbook excludes developer gold, assistant audit labels and model recommendations to reduce anchoring. It does not make you an independent reviewer automatically. Read the approved source under “KB corpus” and export signed decisions for separate verification. No data is uploaded anywhere.</p>
<div class="filters"><label>Reviewer identifier <input id="reviewer" autocomplete="off" placeholder="Organization-assigned reviewer ID (not a personal secret)"></label>
<label>Tenant <select id="tenant"><option value="">Both</option><option value="teamflow-cloud">TeamFlow</option><option value="novamart-store">NovaMart</option></select></label>
<label>Language <select id="locale"><option value="">Both</option><option value="vi">Vietnamese</option><option value="en">English</option></select></label></div>
<p id="progress" class="muted"></p><button id="export">Export manual adjudication JSON (local file only)</button>
<section id="tasks">{''.join(cards)}</section>
<h2>Approved KB corpus — review exact v2 articles</h2><p class="muted">Approved policy material only; statements about real customer outcomes require authorized case records and human action.</p>
{''.join(details)}
<script>
const META={serialized};
const cards=[...document.querySelectorAll('.task')];
const tenant=document.getElementById('tenant'),loc=document.getElementById('locale'),reviewer=document.getElementById('reviewer');
function update(){{
 let count=0,done=0;
 cards.forEach(c=>{{
  const show=(!tenant.value||c.dataset.tenant===tenant.value)&&(!loc.value||c.dataset.locale===loc.value);
  c.hidden=!show;
  if(show){{count++;if(c.querySelector('.verdict').value)done++;}}
 }});
 document.getElementById('progress').textContent=done+'/'+count+' visible claims adjudicated; '+cards.filter(c=>c.querySelector('.verdict').value).length+'/64 overall';
}}
for(const x of document.querySelectorAll('select,textarea'))x.addEventListener('change',update);
document.getElementById('export').addEventListener('click',()=>{{
 const id=reviewer.value.trim();
 if(id.length<3){{alert('Enter reviewer identifier (at least 3 characters).');return;}}
 const decisions=cards.map(c=>({{
  claim_id:c.dataset.id,
  tenant:c.dataset.tenant,locale:c.dataset.locale,
  reviewer_decision:c.querySelector('.verdict').value||null,
  evidence_article:c.querySelector('.article').value||null,
  evidence_quote_or_section:c.querySelector('.evidence').value,
  reviewer_notes:c.querySelector('.reason').value
 }}));
 const bundle={{...META,reviewer_id:id,created_utc:new Date().toISOString(),
  completion:decisions.filter(d=>d.reviewer_decision).length,total:decisions.length,
  decisions}};
 const blob=new Blob([JSON.stringify(bundle,null,2)],{{type:'application/json'}});
 const uri=URL.createObjectURL(blob),a=document.createElement('a');
 a.href=uri;a.download='m2-claim64-human-review-DRAFT.json';a.click();
 setTimeout(()=>URL.revokeObjectURL(uri),500);
}});
update();
</script></main></body></html>'''
OUT.write_text(page)
print(json.dumps({'status':'PASS_OFFLINE_REVIEWER_WORKBOOK_CREATED',
 'file':str(OUT),'bytes':OUT.stat().st_size,
 'sha256':hashlib.sha256(OUT.read_bytes()).hexdigest(),
 'cards':len(cards),'kb_documents':len(details),
 'gold_in_workbook':False,'model_inference':'NOT_RUN'}))
