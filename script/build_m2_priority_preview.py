#!/usr/bin/env python3
"""Static read-only bilingual comparison; never records editorial approval."""
import html
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
proposal = json.loads((ROOT / 'review/m2_priority_editorial_proposals_20261029.json').read_text(encoding='utf-8'))
original = json.loads((ROOT / 'data/m2/knowledge_drafts.json').read_text(encoding='utf-8'))
by_key = {a['article_key']: a for a in original['articles']}
revs = {(r['article_key'],r['locale']): r for r in proposal['revisions']}
keys = ['TF-KB-012','TF-KB-015','NM-KB-014','NM-KB-020','NM-KB-029','NM-KB-030']
esc = html.escape

STEP_HEADINGS = {"Các bước xử lý", "Handling steps"}
POLICY_HEADINGS = {"Chính sách có hiệu lực", "Authoritative policy", "Chính sách đã phê duyệt có liên quan", "Relevant approved policies"}
POLICY_LINE = re.compile(r'^- \*\*([A-Z][A-Z0-9-]+)\*\*\s+—\s+(.+)$')
STEP_MARKER = re.compile(r'(?<!\S)([1-9]\d?)\.\s+')
STEP_SPLIT = re.compile(r'(?<!\S)[1-9]\d?\.\s+')

def render_editorial_body(body):
    """Escape all source text; render steps as semantic ordered HTML list."""
    sections = re.split(r'(?m)^## ([^\n]+)\n', body)
    intro = sections.pop(0).strip()
    if intro and not intro.startswith('# '):
        raise ValueError('Unexpected article introduction')
    parts = ['<div class="kb-content">']
    for heading, copy in zip(sections[::2], sections[1::2]):
        heading = heading.strip()
        copy = copy.strip()
        parts.append(f'<h4>{esc(heading)}</h4>')
        if heading in STEP_HEADINGS:
            markers = [int(match) for match in STEP_MARKER.findall(copy)]
            steps = STEP_SPLIT.split(copy)
            if len(markers) < 2 or markers != list(range(1, len(markers) + 1)) or steps[0] != '' or len(steps) != len(markers) + 1:
                raise ValueError('Cannot safely parse numbered steps: ' + heading)
            parts.append('<ol class="kb-step-list">')
            parts.extend(f'<li>{esc(step.strip())}</li>' for step in steps[1:])
            parts.append('</ol>')
        elif heading in POLICY_HEADINGS:
            lines = copy.splitlines()
            matches = [POLICY_LINE.fullmatch(line.strip()) for line in lines]
            if not lines or not all(matches):
                raise ValueError('Unexpected Markdown policy format in ' + heading)
            parts.append('<ul class="kb-policy-list">')
            parts.extend(f'<li><strong>{esc(match.group(1))}</strong> — {esc(match.group(2))}</li>' for match in matches)
            parts.append('</ul>')
        else:
            parts.append(f'<p class="kb-copy">{esc(copy)}</p>')
    parts.append('</div>')
    return ''.join(parts)

css = '''<style>
:root{color-scheme:dark;font:15px/1.65 system-ui,sans-serif;background:#0b1224;color:#eaf0fc}*{box-sizing:border-box}
body{margin:0}main{max-width:1460px;margin:auto;padding:30px 24px 70px}header{padding-bottom:18px;border-bottom:1px solid #3b4b65}
h1{margin:3px 0;font-size:clamp(26px,4vw,40px)}h2{font-size:21px;margin:32px 0 12px}h3{margin:8px 0}
p{margin:12px 0}a{color:#94c9ff}.intro{color:#b5c4dc}.pill{display:inline-block;border:1px solid #6f6341;background:#2c261c;border-radius:999px;padding:3px 10px;color:#ffe0a1;font-size:12px}
nav{display:flex;gap:8px;flex-wrap:wrap;margin:20px 0 28px}nav a{border:1px solid #3a5377;border-radius:9px;padding:7px 11px;text-decoration:none}
.pair{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px}.item{border:1px solid #324d6d;background:linear-gradient(155deg,#182742,#111e34);border-radius:16px;padding:20px;min-width:0}
.kb-content{max-height:650px;overflow-y:auto;overflow-wrap:anywhere;line-height:1.65;background:#0c162b;padding:18px;border-radius:10px;border:1px solid #344560;font-size:14px}
.kb-content h4{font-size:15px;color:#d6e9ff;margin:20px 0 8px;border-bottom:1px solid #30405c;padding-bottom:6px}
.kb-content h4:first-child{margin-top:0}
.kb-copy{white-space:pre-wrap;margin:5px 0 14px}
.kb-step-list{margin:12px 0 22px;padding-left:30px;display:grid;gap:11px;list-style:decimal}
.kb-step-list li{padding:9px 12px 9px 5px;border-bottom:1px solid #2a405d;line-height:1.6}
.kb-step-list li::marker{font-weight:750;color:#9acaff}
.kb-policy-list{margin:12px 0 20px;padding-left:22px;list-style:disc;display:grid;gap:9px}
.kb-policy-list li{line-height:1.65;padding-left:5px}
.kb-policy-list strong{color:#b5d9ff;font-weight:750}

.meta{color:#a9b9ce;font-size:12px}.hash{font-family:monospace;word-break:break-all}.notice{background:#202a41;border:1px solid #536482;border-radius:10px;padding:13px 17px}footer{color:#a6b4ca;margin-top:40px} @media(max-width:950px){.pair{grid-template-columns:1fr} main{padding:18px}}
</style>'''
page = ['<!DOCTYPE html><html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>M2 · KB bilingual editorial preview</title>',css,'</head><body><main>']
page.append('<header><span class="pill">SOURCE-ONLY · DRAFT · NO APPROVAL</span><h1>KB Editorial Review · VI / EN</h1><p class="intro">12 proposed v2 drafts across 6 policy-sensitive articles · View-only bilingual comparison. These documents are NOT approved or served as customer answers.</p></header>')
page.append('<nav aria-label="Article navigation">')
for key in keys:
 title=by_key[key]['versions'][0]['title']
 page.append(f'<a href="#{esc(key)}">{esc(key)} · {esc(title)}</a>')
page.append('</nav><p class="notice">Kiểm tra nội dung, đối chiếu canonical M0 và các ngày/giới hạn, sau đó đăng nhập Rails bằng vai trò owner/admin để duyệt từng ngôn ngữ. Trang này không cho phép duyệt nội dung.</p>')
for key in keys:
 page.append(f'<section id="{esc(key)}"><h2>{esc(key)} · {esc(by_key[key]["category"])}</h2><div class="pair">')
 for lang in ('vi','en'):
  r=revs[key,lang]
  page.append(f'<article class="item" lang="{lang}"><span class="pill">{lang.upper()} · v2 draft</span><h3>{esc(r["title"])}</h3>')
  page.append(f'<p class="meta">Policies: {esc(", ".join(r["policy_refs"]+r["clarification_refs"]))}</p>')
  page.append(f'<p class="meta hash">SHA256: {esc(r["sha256"])}</p>')
  page.append(render_editorial_body(r["body"]))
  page.append(f'<p class="meta">v1 source: {esc(r["based_on_v1_sha256"][:16])}…</p></article>')
 page.append('</div></section>')
page.append('<footer>Offline preview; no database writes, external requests, approval buttons or automatic publishing.</footer></main></body></html>')
out=ROOT/'preview/m2_priority_editorial';out.mkdir(parents=True,exist_ok=True)
(out/'index.html').write_text(''.join(page),encoding='utf-8')
print('generated',out/'index.html','bytes',(out/'index.html').stat().st_size)
