#!/usr/bin/env python3
"""Standalone, read-only editorial preview; never marks drafts as approved."""
import json, html
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
PAYLOAD=json.loads((ROOT/'data/m2/knowledge_drafts.json').read_text())
OUT=ROOT/'preview/m2_knowledge'; OUT.mkdir(parents=True,exist_ok=True)
NAMES={'teamflow-cloud':'TeamFlow Cloud','novamart-store':'NovaMart Store'}
LANGS={'vi':'Tiếng Việt','en':'English'}
STYLE='''<style>
:root{color-scheme:dark;font-family:system-ui,-apple-system,sans-serif;background:#0b1222;color:#e9f2ff}*{box-sizing:border-box}body{max-width:1400px;margin:auto;padding:28px 30px}a{color:#a6c9ff;text-decoration:none}.header{border-bottom:1px solid #354c67;padding-bottom:18px}.muted{color:#9cafd1}.tag{display:inline-block;border-radius:999px;background:#402b19;color:#fbd093;border:1px solid #815f2b;padding:6px 11px;font-size:12px}.nav{display:flex;flex-wrap:wrap;gap:14px;margin:20px 0}a.choice{padding:9px 14px;background:#1c2f4a;border:1px solid #345778;border-radius:10px}.layout{display:grid;grid-template-columns:300px minmax(0,1fr);gap:20px;margin-top:26px}aside{position:sticky;top:16px;align-self:start;max-height:90vh;overflow:auto;padding:17px;border:1px solid #31445c;border-radius:16px;background:#151f32}.article{margin:8px 0;border-radius:9px;padding:10px;background:#1c2941;border:1px solid #2d405d;cursor:pointer;font-size:13px}.article[open]{border-color:#78a9e2}.article summary{font-weight:600;cursor:pointer}.article pre{display:none}main{min-width:0}.body{margin-top:16px;background:#19253b;border:1px solid #304562;border-radius:16px;padding:27px}.body pre{font-family:system-ui,sans-serif;white-space:pre-wrap;line-height:1.8;font-size:14px;overflow-wrap:anywhere}.search{width:100%;padding:12px;background:#0e1829;border:1px solid #4d6789;color:white;border-radius:9px}.selected{border-color:#a7c9fe!important;background:#263c60!important}.proof{font-size:12px;color:#8caad0;word-wrap:break-word}@media(max-width:850px){body{padding:15px}.layout{display:block}aside{position:static;max-height:320px;margin-bottom:18px}}</style>'''
SCRIPT='''<script>
const cards=Array.from(document.querySelectorAll('.article'));
const titleEl=document.getElementById('heading'),bodyEl=document.getElementById('body'),refsEl=document.getElementById('refs');
function show(card){cards.forEach(x=>x.classList.toggle('selected',x===card));titleEl.textContent=card.dataset.title;bodyEl.textContent=card.querySelector('template').content.textContent;refsEl.textContent='ID: '+card.dataset.id+' · Policies: '+(card.dataset.policy||'none')+' · SHA256: '+card.dataset.sha;location.hash=card.dataset.id;}
cards.forEach(c=>c.addEventListener('click',()=>show(c)));
document.getElementById('filter').addEventListener('input',e=>{const q=e.target.value.toLocaleLowerCase().trim();cards.forEach(c=>c.hidden=!c.dataset.search.includes(q));});
const selected=cards.find(c=>c.dataset.id===location.hash.slice(1))||cards[0];if(selected)show(selected);
</script>'''

def safe(x):return html.escape(str(x),quote=True)

def page(org,locale):
    arts=[a for a in PAYLOAD['articles'] if a['organization_slug']==org]
    cards=[]
    for a in arts:
        v=next(v for v in a['versions'] if v['locale']==locale)
        terms=(' '.join((a['article_key'],a['category'],v['title'],','.join(a['policy_refs']),v['body']))).lower()
        # HTML template keeps raw content inert until explicitly selected.
        cards.append(f'<div class="article" data-id="{safe(a["article_key"])}" data-title="{safe(v["title"])}" data-sha="{safe(v["sha256"])}" data-policy="{safe(", ".join(a["policy_refs"]))}" data-search="{safe(terms)}"><strong>{safe(a["article_key"])}</strong><div>{safe(v["title"])}</div><small class="muted">{safe(a["category"])} · {safe(a["audience"])}</small><template>{safe(v["body"])}</template></div>')
    links=''.join(f'<a class="choice" href="{o}-{loc}.html">{safe(NAMES[o])} · {safe(LANGS[loc])}</a>' for o in NAMES for loc in LANGS)
    heading='Bản nháp đang chờ duyệt' if locale=='vi' else 'Editorial drafts awaiting approval'
    subtitle=('Bản xem trước tĩnh, không phải dữ liệu KB đã phát hành. Chỉ owner/admin Rails có quyền duyệt từng phiên bản sau khi kiểm tra.' if locale=='vi' else 'Static preview, not published KB. Only an authorized Rails owner/admin can approve individual reviewed versions.')
    return f'''<!doctype html><html lang="{locale}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{safe(NAMES[org])} — KB {locale}</title>{STYLE}</head><body><header class="header"><span class="tag">M2 · DRAFT · NO AI EMBEDDINGS</span><h1>{safe(NAMES[org])} · {safe(LANGS[locale])}</h1><h2>{safe(heading)}</h2><p class="muted">{safe(subtitle)}</p></header><nav class="nav">{links}</nav><div class="layout"><aside><label for="filter">Search / Tìm kiếm · {len(arts)} articles</label><p><input id="filter" class="search" placeholder="ID, title, policy, content..." autocomplete="off"></p>{''.join(cards)}</aside><main><section class="body"><h2 id="heading"></h2><div class="tag">DRAFT / NOT APPROVED</div><p class="proof" id="refs"></p><pre id="body"></pre></section></main></div>{SCRIPT}</body></html>'''

for o in NAMES:
    for l in LANGS:
        (OUT/f'{o}-{l}.html').write_text(page(o,l),encoding='utf-8')
index='''<!doctype html><html><head><meta charset="utf-8"><title>M2 Knowledge Editorial Review</title>'''+STYLE+'''</head><body><h1>M2 · Knowledge Editorial Review</h1><p class="tag">100 synthetic KB articles · 200 language versions · DRAFT ONLY</p><div class="nav">'''+''.join(f'<a class="choice" href="{o}-{l}.html">{safe(NAMES[o])} · {safe(LANGS[l])}</a>' for o in NAMES for l in LANGS)+'''</div><p class="muted">This offline preview is NOT a published knowledge base and does not prove AI retrieval or inference.</p></body></html>'''
(OUT/'index.html').write_text(index,encoding='utf-8')
print('Created',len(list(OUT.glob('*.html'))),'offline editorial HTML pages')
