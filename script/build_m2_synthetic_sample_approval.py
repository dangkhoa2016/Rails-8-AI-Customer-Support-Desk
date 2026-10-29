#!/usr/bin/env python3
"""Owner policy: accept every frozen synthetic claim as DEMO INPUT, not policy truth.
Produce additive immutable sample-acceptance manifest and static bilingual previews.
NEVER modify original review queue, approved KB, DB approval flags or AI gate.
"""
from pathlib import Path
from html import escape
from collections import Counter
import hashlib
import json

ROOT=Path(__file__).resolve().parents[1]
QUEUE=ROOT/"evidence-m2-claim32x2-20261029/claim-level-blind-human-validation.json"
KB=ROOT/"evidence-m2-claim64-provisional-audit-20261029/approved-kb-v2-readonly-snapshot.json"
OUT=ROOT/"review/m2_claim64_synthetic_demo_approval_20261029.json"
HTML=ROOT/"evidence-m2-claim64-independent-review-v2-20261029"
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def h(x):return escape(str(x),quote=True)
q=json.loads(QUEUE.read_bytes())
k=json.loads(KB.read_bytes())
assert len(q["tasks"])==64 and len(k["articles"])==12
assert len({r["claim_id"] for r in q["tasks"]})==64
assert Counter((r["tenant"],r["locale"]) for r in q["tasks"])=={
  ("teamflow-cloud","vi"):16,("teamflow-cloud","en"):16,
  ("novamart-store","vi"):16,("novamart-store","en"):16}
for a in k["articles"]:
    assert hashlib.sha256(a["body"].encode("utf-8")).hexdigest()==a["body_sha256"]

records=[]
for row in q["tasks"]:
    assert row["human_decision_status"]=="PENDING_MANUAL_VERIFICATION"
    assert row["human_policy_supported"] is None
    records.append({
       "claim_id":row["claim_id"],"tenant":row["tenant"],"locale":row["locale"],
       "parent_question":row["parent_question"],"atomic_claim":row["atomic_claim"],
       "sample_content_status":"APPROVED_FOR_SYNTHETIC_DEMO",
       "human_semantic_review":"NOT_PERFORMED_NOT_REQUIRED_FOR_SAMPLE_PRESENTATION",
       "policy_answerability":"UNKNOWN_NOT_APPROVED",
       "real_world_truth":"NOT_VERIFIED"
    })
kb_records=[{
  "tenant":a["tenant"],"locale":a["locale"],"article_key":a["article_key"],
  "approved_version":a["article_version_number"],"policy_version":a["policy_version"],
  "body_sha256":a["body_sha256"],
  "sample_content_status":"APPROVED_FOR_SYNTHETIC_DEMO",
  "existing_kb_approval":"PRESERVED_AS_IN_SOURCE_SNAPSHOT",
  "real_world_truth":"NOT_VERIFIED"} for a in k["articles"]]
manifest={
  "kind":"RAILS8_M2_OWNER_DEFAULT_SYNTHETIC_SAMPLE_ACCEPTANCE_V1",
  "decision_date":"2026-10-29",
  "decision_origin":"USER_APPROVED_SYNTHETIC_DEMO_DATA_BY_DEFAULT",
  "scope":"CONTENT_FOR_LOCAL_DEMO_PRESENTATION_AND_RELEVANCE_ONLY_RESEARCH",
  "dataset_sample_status":"APPROVED_FOR_SYNTHETIC_DEMO",
  "real_world_accuracy":"NOT_VERIFIED_DO_NOT_PRESENT_AS_REAL_WORLD_POLICY",
  "frozen_claim_queue_sha256":sha(QUEUE),
  "frozen_approved_kb_snapshot_sha256":sha(KB),
  "claim_count":64,"claims_accepted_for_demo":64,
  "approved_kb_source_count":12,"approved_kb_accepted_for_demo":12,
  "claims":records,"kb_articles":kb_records,
  "human_review_requirement_for_sample_display":"WAIVED_BY_OWNER_ONLY_FOR_SYNTHETIC_DEMO",
  "human_reviewer_labels_or_signatures_created":False,
  "atomic_policy_truth_assumed":False,
  "all_claims_assumed_affirmative":False,
  "retrieval_access":"PRESERVE_ONLY_EXISTING_APPROVED_KB_VERSIONS_AND_TENANT_LOCALE",
  "db_article_version_states":"UNCHANGED",
  "scope_gate":"BLOCKED_PREVIOUS_SEALED80_FALSE_POSITIVES",
  "automated_customer_answer":"NOT_AUTHORIZED",
  "ai_business_writes":"PROHIBITED",
  "revenue_billing_entitlement_shipping_refund_write_permissions":"PROHIBITED",
  "production_readiness":"NOT_CLAIMED",
  "release_mode":"SYNTHETIC_DEMO_CONTENT_ONLY",
  "manual_review_workbook_status":"OPTIONAL_FUTURE_VALIDATION_NOT_A_DEMO_PREREQUISITE"
}
assert not OUT.exists(),"No overwrite"
OUT.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n")
assert len(records)==64 and len(kb_records)==12

terms={
 "vi":{
  "title":"Dữ liệu mẫu — được chấp nhận cho demo",
  "subtitle":"TeamFlow Cloud + NovaMart Store · Hai doanh nghiệp giả lập · 29/10/2026",
  "warning":"Đây là dữ liệu mẫu được chủ dự án mặc định chấp nhận để minh họa. Chưa xác minh đúng với thực tế; không có nghĩa AI được tự trả lời, tự hoàn tiền hoặc thay đổi dữ liệu. 64 claim là câu hỏi thử nghiệm, không phải 64 câu trả lời đúng.",
  "claims":"Mệnh đề mẫu được duyệt","articles":"Bài KB approved v2 thuộc phạm vi nghiên cứu",
  "strata":"Nhóm tenant/ngôn ngữ","status":"Chấp nhận làm mẫu",
  "filter":"Lọc theo doanh nghiệp","all":"Tất cả","tf":"TeamFlow Cloud","nm":"NovaMart Store",
  "locale":"Ngôn ngữ","both":"Cả hai","vi":"Tiếng Việt","en":"Tiếng Anh",
  "question":"Câu hỏi tổng hợp","claim":"Mệnh đề thử nghiệm",
  "kb":"KB tham chiếu · mẫu synthetic","source":"Nguồn KB approved đang dùng cho nghiên cứu",
  "nohuman":"Không cần hai người reviewer để hiển thị dữ liệu mẫu",
  "nottruth":"Không xác nhận đúng chính sách ngoài đời thực","notrelease":"AI answerability / business writes vẫn bị khóa",
  "form":"Mở phiếu review tùy chọn","footer":"Giữ nguyên KB, trạng thái database và các chốt an toàn từ sealed80. Không được coi sample approval là semantic gold hoặc authorization.",
  "switch":"English version"
 },
 "en":{
  "title":"Synthetic sample data — accepted for demo",
  "subtitle":"TeamFlow Cloud + NovaMart Store · Fictional businesses · October 29, 2026",
  "warning":"The project owner accepts these synthetic samples by default for demonstration. Their real-world accuracy has NOT been verified. This does not authorize AI answers, refunds, account changes, or business writes. The 64 claims are test questions, not 64 validated correct answers.",
  "claims":"Sample claims accepted","articles":"Approved v2 KB articles in the research subset",
  "strata":"Tenant/language strata","status":"Sample accepted",
  "filter":"Tenant filter","all":"All","tf":"TeamFlow Cloud","nm":"NovaMart Store",
  "locale":"Language","both":"Both","vi":"Vietnamese","en":"English",
  "question":"Composite question","claim":"Test claim",
  "kb":"Reference KB · synthetic only","source":"Currently approved KB source for research",
  "nohuman":"No dual-human review required to display sample data",
  "nottruth":"No real-world policy accuracy claim","notrelease":"AI answerability / writes remain blocked",
  "form":"Optional human review form","footer":"Existing KB, DB status, sealed80 fail-closed gates and human approval for business writes remain unchanged. Sample approval is not semantic gold or authorization.",
  "switch":"Bản tiếng Việt"
 }
}
tmpl=r'''<!doctype html><html lang="@@LANG@@"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>@@TITLE@@</title><style>
:root{color-scheme:dark;font:16px system-ui,sans-serif}*{box-sizing:border-box}body{margin:0;background:#0d1828;color:#edf4ff}
main{max-width:1180px;margin:0 auto;padding:24px 18px}header{display:flex;justify-content:space-between;align-items:center;gap:12px;flex-wrap:wrap}
h1{font-size:clamp(1.7rem,3vw,2.6rem);margin:12px 0}small,.muted{color:#b7c9e1}a{color:#aacdff}
.notice{padding:16px;background:#302618;border:1px solid #b18b4d;border-radius:10px;line-height:1.6}
.metrics{display:flex;flex-wrap:wrap;gap:12px;margin:22px 0}.metric{min-width:190px;flex:1;border:1px solid #476585;border-radius:10px;background:#162a43;padding:16px}
.metric b{display:block;font-size:2rem}.metric small{line-height:1.6}
.filters{display:flex;flex-wrap:wrap;gap:16px;margin:22px 0}.filters label{flex:1;min-width:190px}
select{display:block;width:100%;margin-top:8px;padding:10px;color:#edf4ff;border:1px solid #6785a7;border-radius:8px;background:#152e47;font:inherit}
.card{padding:16px 20px;border:1px solid #476585;background:#152940;border-radius:10px;margin:14px 0}
.card[hidden]{display:none}.card h3{font-size:1rem;margin:5px 0}.card p{line-height:1.6}
.tag{font-size:.8rem;color:#92e6bd;letter-spacing:.03em}.question{color:#d1dff1}
.kb article{padding:15px;border:1px solid #476585;border-radius:9px;margin:12px 0}
pre{white-space:pre-wrap;word-break:break-word}code{overflow-wrap:anywhere}
</style></head><body><main>
<header><small>Rails 8 AI Customer Support Desk</small><a href="@@OTHER@@">@@SWITCH@@</a></header>
<h1>@@TITLE@@</h1><p class="muted">@@SUBTITLE@@</p><p class="notice">@@WARNING@@</p>
<section class="metrics">
<div class="metric"><b>64 / 64</b><small>@@CLAIMS@@</small></div>
<div class="metric"><b>12 / 12</b><small>@@ARTICLES@@</small></div>
<div class="metric"><b>4 × 16</b><small>@@STRATA@@</small></div>
</section>
<p><strong>@@NOHUMAN@@</strong> · @@NOTTRUTH@@ · @@NOTRELEASE@@</p>
<div class="filters"><label>@@FILTER@@<select id="tenant"><option value="">@@ALL@@</option>
<option value="teamflow-cloud">@@TF@@</option><option value="novamart-store">@@NM@@</option></select></label>
<label>@@LOCALE@@<select id="locale"><option value="">@@BOTH@@</option>
<option value="vi">@@VI@@</option><option value="en">@@EN@@</option></select></label></div>
<p id="count" class="muted"></p>
<section id="claims">@@CARDS@@</section>
<h2>@@SOURCE@@</h2><p class="muted">SHA256 queue: <code>@@QUEUE_SHA@@</code></p>
<p class="muted">SHA256 KB snapshot: <code>@@KB_SHA@@</code></p>
<div class="kb">@@KBDOCS@@</div>
<p><a href="@@REVIEW_FORM@@">@@FORM@@</a></p>
<p class="notice">@@FOOTER@@</p>
<script>
"use strict";
const t=document.getElementById("tenant"),l=document.getElementById("locale");
const rows=[...document.querySelectorAll("article.sample-claim")],count=document.getElementById("count");
function update(){let shown=0;for(const c of rows){
 const visible=(!t.value||c.dataset.tenant===t.value)&&(!l.value||c.dataset.locale===l.value);
 c.hidden=!visible;if(visible)shown++;
}count.textContent=shown+" / 64";}
t.addEventListener("change",update);l.addEventListener("change",update);update();
</script></main></body></html>'''
for lang,t in terms.items():
    cards=[]
    for i,item in enumerate(records,1):
        cards.append(f'''<article class="card sample-claim" data-tenant="{h(item["tenant"])}" data-locale="{h(item["locale"])}">
<header><h3>{i:02} · {h(item["claim_id"])}</h3><span class="tag">{h(t["status"])} · {h(item["locale"].upper())}</span></header>
<p class="question"><strong>{h(t["question"])}:</strong> {h(item["parent_question"])}</p>
<p><strong>{h(t["claim"])}:</strong> {h(item["atomic_claim"])}</p></article>''')
    docs="".join(f'''<article><strong>{h(a["article_key"])} · {h(a["tenant"])} / {h(a["locale"])} · v{a["approved_version"]}</strong>
<p class="muted">{h(t["kb"])} · SHA256 <code>{h(a["body_sha256"])}</code></p></article>''' for a in kb_records)
    vals={key.upper():h(value) for key,value in t.items() if key not in ("question","claim","status","kb")}
    vals.update({"LANG":lang,"CARDS":"".join(cards),"KBDOCS":docs,
      "QUEUE_SHA":sha(QUEUE),"KB_SHA":sha(KB),
      "OTHER":"sample-approval.en.html" if lang=="vi" else "sample-approval.vi.html",
      "REVIEW_FORM":"index.vi.html" if lang=="vi" else "index.en.html"})
    page=tmpl
    for key,val in vals.items():page=page.replace("@@"+key+"@@",val)
    assert "@@" not in page
    assert page.count('class="card sample-claim"')==64
    assert page.count('<article><strong>')==12
    assert "fetch(" not in page and "localStorage" not in page
    dest=HTML/f"sample-approval.{lang}.html"
    assert not dest.exists()
    dest.write_text(page)
    print(json.dumps({"page":str(dest),"sha256":sha(dest),"bytes":dest.stat().st_size,
        "sample_accepted_claims":64,"approved_kb_source_count":12}))
print(json.dumps({"manifest":str(OUT),"sha256":sha(OUT),"sample_claims_accepted":64,
   "review_waived_for_demo":True,"semantic_answerability":"NOT_CERTIFIED",
   "business_writes":"PROHIBITED"}))
