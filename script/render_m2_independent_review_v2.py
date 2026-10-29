#!/usr/bin/env python3
"""Generate two BLIND offline reviewer workbooks from frozen synthetic KB.
A reviewer must make every decision; no AI / developer labels are embedded.
"""
from pathlib import Path
from html import escape
import hashlib
import json

ROOT=Path(__file__).resolve().parents[1]
QUEUE=ROOT/"evidence-m2-claim32x2-20261029/claim-level-blind-human-validation.json"
KB=ROOT/"evidence-m2-claim64-provisional-audit-20261029/approved-kb-v2-readonly-snapshot.json"
OUT=ROOT/"evidence-m2-claim64-independent-review-v2-20261029"
q=json.loads(QUEUE.read_text())
snap=json.loads(KB.read_text())
assert len(q["tasks"])==64 and len(snap["articles"])==12
assert len(set(t["claim_id"] for t in q["tasks"]))==64
for a in snap["articles"]:
    assert hashlib.sha256(a["body"].encode("utf-8")).hexdigest()==a["body_sha256"]
META={"source_manifest_sha256":q["source_manifest_sha256"],
      "candidate_evidence_sha256":q["model_evidence_sha256"],
      "approved_snapshot_sha256":hashlib.sha256(KB.read_bytes()).hexdigest()}
docs={(d["tenant"],d["locale"],d["article_key"]):d["body"] for d in snap["articles"]}
def safe(obj):
    return json.dumps(obj,ensure_ascii=False).replace("<","\\u003c").replace(">","\\u003e").replace("&","\\u0026")
def h(s):return escape(str(s),quote=True)
TRANSLATIONS={
 "vi":{
  "title":"Kiểm duyệt độc lập 64 mệnh đề",
  "warning":"Dữ liệu giả lập. Không hiển thị nhãn AI hoặc nhãn developer. Hãy tự đọc KB approved và đưa ra kết luận. Không tự lưu dữ liệu trên trình duyệt; hãy xuất bản nháp định kỳ. File này không xác minh danh tính hay tính độc lập.",
  "reviewer":"Mã người kiểm duyệt (do đơn vị cấp, không phải bí mật)",
  "tenant":"Doanh nghiệp","locale":"Ngôn ngữ câu hỏi",
  "all":"Tất cả","both":"Cả hai","vi":"Tiếng Việt","en":"Tiếng Anh",
  "unfinished":"Chỉ hiển thị mệnh đề chưa đạt",
  "import":"Nhập bản nháp JSON",
  "draft":"Xuất JSON nháp về máy",
  "finish":"Xuất JSON hoàn tất, tự xác nhận",
  "next":"Đến mục chưa hoàn tất",
  "attest":"Tôi đã tự mình kiểm tra 64 mệnh đề, không sử dụng dự đoán AI, nhãn developer hoặc quyết định của reviewer khác. Đây chỉ là tự xác nhận, không phải xác minh danh tính.",
  "parent":"Câu hỏi tổng hợp","atom":"Mệnh đề cần phân xử",
  "verdict":"Kết luận dựa trên KB approved",
  "choose":"Chọn kết luận sau khi đọc KB",
  "affirm":"Chính sách cho phép trả lời Có / có điều kiện",
  "negative":"Chính sách rõ ràng hỗ trợ câu trả lời Không",
  "undocumented":"Chưa được tài liệu hóa, không có câu trả lời an toàn",
  "uncertain":"Chưa chắc chắn, cần người khác phân xử",
  "article":"Bài KB cùng tenant/ngôn ngữ",
  "none":"Không có / chưa quyết định",
  "source":"Hiển thị văn bản KB của bài đã chọn",
  "quote":"Trích chính xác nguyên văn KB, ít nhất 20 ký tự",
  "copy":"Dùng đoạn KB được bôi đen làm trích dẫn",
  "notes":"Lý do phân loại / dữ liệu case còn thiếu / nguồn đã rà soát",
  "corpus":"Bộ KB synthetic đã approved",
  "progress":"Tiến độ","noauto":"Không có tự lưu; tải JSON trước khi thoát.",
  "footer":"Hai bản đánh giá trùng nhau cũng chưa chứng minh kết luận đúng. Cần người thật phân xử bất đồng, xác minh tính độc lập và ký duyệt; M2 vẫn NOT_RELEASE.",
  "switch":"English version"
 },
 "en":{
  "title":"Independent review of 64 atomic claims",
  "warning":"Synthetic data. AI/developer labels are intentionally excluded. Read the approved KB and make independent decisions. The browser does not autosave; export local drafts regularly. This workbook cannot authenticate a reviewer or establish independence.",
  "reviewer":"Organization-assigned reviewer ID (not a secret)",
  "tenant":"Tenant","locale":"Question language",
  "all":"All","both":"Both","vi":"Vietnamese","en":"English",
  "unfinished":"Show unfinished / invalid claims only",
  "import":"Import local draft JSON",
  "draft":"Export draft JSON locally",
  "finish":"Export completed self-attested JSON",
  "next":"Jump to next unfinished claim",
  "attest":"I assessed all 64 claims myself without consulting model predictions, developer labels, or another reviewer's decisions. This is self-attestation, not identity verification.",
  "parent":"Composite question","atom":"Atomic claim",
  "verdict":"Answerability from the approved KB",
  "choose":"Choose only after reading the KB",
  "affirm":"Policy allows affirmative/conditional answer",
  "negative":"Policy explicitly supports a negative (No) answer",
  "undocumented":"Not documented; no safe policy answer",
  "uncertain":"Uncertain; require independent human arbitration",
  "article":"Approved article from the same tenant/language",
  "none":"None / not selected",
  "source":"Show exact approved-KB article",
  "quote":"Verbatim approved-KB quotation (at least 20 characters)",
  "copy":"Use the highlighted KB text as an exact quotation",
  "notes":"Rationale / missing case facts / sources examined",
  "corpus":"Approved synthetic KB corpus",
  "progress":"Progress","noauto":"No autosave; download your draft before leaving.",
  "footer":"Agreement between reviewers does not prove correctness. Independent identity checks, arbitration, human signoff, and a separate sealed holdout are still required. M2 remains NOT_RELEASE.",
  "switch":"Bản tiếng Việt"
 }
}

TEMPLATE=r'''<!doctype html><html lang="@@LANG@@"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>@@TITLE@@</title>
<style>
:root{color-scheme:dark;font:16px system-ui,sans-serif}*{box-sizing:border-box}
body{background:#0c192b;color:#edf4ff;margin:0}main{max-width:1120px;margin:auto;padding:24px 18px}
h1{font-size:clamp(1.5rem,3vw,2.3rem)}p{line-height:1.52}
a{color:#afceff}.warning{padding:16px;border:1px solid #b28d4d;background:#33291b;border-radius:10px}
.controls,.toolbar{display:flex;flex-wrap:wrap;gap:12px;align-items:end;margin:18px 0}
.controls>label{min-width:175px;flex:1}label{display:block;margin:12px 0;font-weight:600}
input,select,textarea{display:block;width:100%;margin-top:6px;background:#182b45;border:1px solid #6986aa;border-radius:7px;color:#f7fbff;padding:10px;font:inherit}
button{background:#a6cbff;color:#082139;border:0;border-radius:8px;font:inherit;font-weight:650;padding:11px 15px;cursor:pointer}
button:disabled{opacity:.45;cursor:not-allowed}article{padding:18px;background:#142b45;border:1px solid #456586;border-radius:10px;margin:16px 0}
article[hidden]{display:none}.atomic{background:#213d5d;border-radius:7px;padding:13px}
header{display:flex;justify-content:space-between;gap:8px;flex-wrap:wrap}
small,.muted{color:#b6cbe4}pre{white-space:pre-wrap;word-break:break-word;line-height:1.5}
details{border:1px solid #456586;border-radius:8px;padding:12px;margin:13px 0}
details pre{max-height:360px;overflow:auto}code{overflow-wrap:anywhere}.tick{display:flex;align-items:start;gap:10px;font-weight:500}
.tick input{width:auto;margin:5px 0}.progress{position:sticky;top:0;background:#19304d;border:1px solid #58799e;padding:12px;border-radius:8px;z-index:3}
.good{color:#83e3b7}.bad{color:#ffbcb2}
</style></head><body><main><small>Rails 8 AI Customer Support Desk · 2026-10-29 · <a href="@@OTHER@@">@@SWITCH@@</a></small>
<h1>@@TITLE@@</h1><p class="warning">@@WARNING@@</p><p class="muted">@@NOAUTO@@</p>
<div class="controls">
<label>@@REVIEWER@@<input id="reviewer" autocomplete="off" placeholder="Reviewer ID"></label>
<label>@@TENANT@@<select id="tenant"><option value="">@@ALL@@</option><option value="teamflow-cloud">TeamFlow Cloud</option><option value="novamart-store">NovaMart Store</option></select></label>
<label>@@LOCALE@@<select id="locale"><option value="">@@BOTH@@</option><option value="vi">@@VI@@</option><option value="en">@@EN@@</option></select></label>
<label>@@UNFINISHED@@<input id="unfinished" type="checkbox"></label>
</div>
<div class="toolbar"><label>@@IMPORT@@<input type="file" id="import" accept=".json,application/json"></label>
<button type="button" id="draft">@@DRAFT@@</button><button type="button" id="next">@@NEXT@@</button></div>
<label class="tick"><input type="checkbox" id="attest"><span>@@ATTEST@@</span></label>
<div class="toolbar"><button type="button" id="finish" disabled>@@FINISH@@</button></div>
<p class="progress" id="progress"></p>
<section>@@CARDS@@</section><h2>@@CORPUS@@</h2>@@ARTICLES@@
<p class="warning">@@FOOTER@@</p>
<script>
"use strict";
const META=@@META@@, KB=@@KB@@;
const cards=[...document.querySelectorAll("article.task")];
const $=s=>document.querySelector(s);
const labels=new Set(["affirmative_policy","explicit_negative_policy","not_documented","uncertain_needs_second_reviewer"]);
const field=(c,cls)=>c.querySelector("."+cls);
function getDecision(c){return {claim_id:c.dataset.id,tenant:c.dataset.tenant,locale:c.dataset.locale,
 reviewer_decision:field(c,"verdict").value||null,
 evidence_article:field(c,"article").value||null,
 evidence_quote_or_section:field(c,"quote").value,
 reviewer_notes:field(c,"notes").value};}
function check(c){
 const d=getDecision(c),v=d.reviewer_decision,n=d.reviewer_notes.trim(),q=d.evidence_quote_or_section.trim();
 if(!v||!labels.has(v))return "PENDING";
 if(v==="uncertain_needs_second_reviewer")return n.length>=20?"UNCERTAIN":"NEEDS_REASON";
 if(v==="not_documented")return !d.evidence_article&&n.length>=20?"VALID":"NEEDS_REASON_AND_NO_CITATION";
 if(!d.evidence_article)return "NEEDS_APPROVED_SOURCE";
 const body=KB[c.dataset.tenant+"/"+c.dataset.locale+"/"+d.evidence_article];
 if(!body||q.length<20||!body.includes(q))return "NEEDS_EXACT_KB_QUOTE";
 return "VALID";
}
function update(){
 let valid=0,uncertain=0,visible=0;
 for(const c of cards){
  const st=check(c);valid+=st==="VALID";uncertain+=st==="UNCERTAIN";
  field(c,"status").textContent=st;field(c,"status").className="status "+(st==="VALID"?"good":"bad");
  const show=(!$("select#tenant").value||$("select#tenant").value===c.dataset.tenant)
   &&(!$("select#locale").value||$("select#locale").value===c.dataset.locale)
   &&(!$("input#unfinished").checked||st!=="VALID");
  c.hidden=!show;visible+=show;
 }
 const canFinish=valid===64&&$("#reviewer").value.trim().length>=3&&$("#attest").checked;
 $("#finish").disabled=!canFinish;
 $("#progress").textContent="@@PROGRESS@@: "+valid+"/64; "+uncertain+" uncertain; "+visible+" visible; final export "+(canFinish?"enabled":"blocked");
}
for(const c of cards){
 field(c,"article").addEventListener("change",()=>{
  const key=c.dataset.tenant+"/"+c.dataset.locale+"/"+field(c,"article").value;
  field(c,"source-body").textContent=KB[key]||"";update();
 });
 field(c,"quote-selected").addEventListener("click",()=>{
  const key=c.dataset.tenant+"/"+c.dataset.locale+"/"+field(c,"article").value;
  const selected=window.getSelection().toString().trim();
  if(selected.length>=20&&(KB[key]||"").includes(selected)){
    field(c,"quote").value=selected;update();
  }else alert("Select an exact quotation of at least 20 characters inside the chosen approved article.");
 });
 c.querySelectorAll("select,textarea").forEach(el=>el.addEventListener("input",update));
}
["#reviewer","#tenant","#locale","#attest","#unfinished"].forEach(s=>$(s).addEventListener("input",update));
$("#next").addEventListener("click",()=>{
 const target=cards.find(c=>check(c)!=="VALID");
 if(target){$("#tenant").value="";$("#locale").value="";$("#unfinished").checked=false;update();target.scrollIntoView();}
});
function exportLocal(final){
 if($("#reviewer").value.trim().length<3)return alert("Reviewer ID is required (3+ characters).");
 if(final&&$("#finish").disabled)return alert("Complete all claims and self-attest before final export.");
 const ds=cards.map(getDecision);
 const payload={...META,review_status:final?"COMPLETE_SELF_ATTESTED_UNVERIFIED":"DRAFT_UNVERIFIED_REQUIRES_EXTERNAL_HUMAN_SIGNOFF",
 self_attested_independent_review:Boolean(final&&$("#attest").checked),
 reviewer_id:$("#reviewer").value.trim(),created_utc:new Date().toISOString(),
 completion:ds.filter(d=>labels.has(d.reviewer_decision)).length,total:64,decisions:ds};
 const blob=new Blob([JSON.stringify(payload,null,2)],{type:"application/json"});
 const u=URL.createObjectURL(blob),a=document.createElement("a");
 a.href=u;a.download=final?"m2-claim64-human-self-attested-UNVERIFIED.json":"m2-claim64-human-DRAFT.json";
 a.click();setTimeout(()=>URL.revokeObjectURL(u),2000);
}
$("#draft").addEventListener("click",()=>exportLocal(false));
$("#finish").addEventListener("click",()=>exportLocal(true));
$("#import").addEventListener("change",async ev=>{
 const file=ev.target.files?.[0];if(!file)return;
 try{
  if(file.size>3000000)throw Error("Too large");
  const data=JSON.parse(await file.text());
  if(!["source_manifest_sha256","candidate_evidence_sha256","approved_snapshot_sha256"].every(k=>data[k]===META[k]))
   throw Error("Source/KB checksum mismatch");
  if(data.total!==64||!Array.isArray(data.decisions)||data.decisions.length!==64)throw Error("Wrong decision count");
  const map=new Map();
  for(const d of data.decisions){if(!d||map.has(d.claim_id))throw Error("Duplicate/invalid ID");map.set(d.claim_id,d);}
  for(const c of cards){const d=map.get(c.dataset.id);
    if(!d||d.tenant!==c.dataset.tenant||d.locale!==c.dataset.locale)throw Error("Missing or cross-tenant claim");}
  $("#reviewer").value=typeof data.reviewer_id==="string"?data.reviewer_id:"";
  for(const c of cards){
   const d=map.get(c.dataset.id);
   field(c,"verdict").value=labels.has(d.reviewer_decision)?d.reviewer_decision:"";
   field(c,"article").value=typeof d.evidence_article==="string"?d.evidence_article:"";
   field(c,"quote").value=typeof d.evidence_quote_or_section==="string"?d.evidence_quote_or_section:"";
   field(c,"notes").value=typeof d.reviewer_notes==="string"?d.reviewer_notes:"";
   field(c,"source-body").textContent=KB[c.dataset.tenant+"/"+c.dataset.locale+"/"+field(c,"article").value]||"";
  }
  $("#attest").checked=false;update();alert("Draft imported locally. Review source citations before final self-attestation.");
 }catch(err){alert("Import rejected: "+String(err.message||err));}
 ev.target.value="";
});
update();
</script></main></body></html>'''
OUT.mkdir(exist_ok=True)
for lang,t in TRANSLATIONS.items():
    cards=[]
    for i,claim in enumerate(q["tasks"],1):
        available=[d for d in snap["articles"] if d["tenant"]==claim["tenant"] and d["locale"]==claim["locale"]]
        options="".join(f'<option value="{h(d["article_key"])}">{h(d["article_key"])} · v{d["article_version_number"]}</option>' for d in available)
        cards.append(f'''<article class="task" data-id="{h(claim["claim_id"])}" data-tenant="{h(claim["tenant"])}" data-locale="{h(claim["locale"])}">
<header><strong>{i}/64 · {h(claim["claim_id"])}</strong><span>{h(claim["tenant"])} · {h(claim["locale"].upper())}</span></header>
<p><small>{h(t["parent"])}:</small> {h(claim["parent_question"])}</p>
<p class="atomic"><strong>{h(t["atom"])}:</strong> {h(claim["atomic_claim"])}</p>
<label>{h(t["verdict"])}<select class="verdict"><option value="">{h(t["choose"])}</option>
<option value="affirmative_policy">{h(t["affirm"])}</option><option value="explicit_negative_policy">{h(t["negative"])}</option>
<option value="not_documented">{h(t["undocumented"])}</option><option value="uncertain_needs_second_reviewer">{h(t["uncertain"])}</option></select></label>
<label>{h(t["article"])}<select class="article"><option value="">{h(t["none"])}</option>{options}</select></label>
<details><summary>{h(t["source"])}</summary><pre class="source-body"></pre><button type="button" class="quote-selected">{h(t["copy"])}</button></details>
<label>{h(t["quote"])}<textarea class="quote" spellcheck="false" rows="2"></textarea></label>
<label>{h(t["notes"])}<textarea class="notes" rows="2"></textarea></label>
<p class="status"></p></article>''')
    articles="".join(f'<details class="kb"><summary>{h(d["tenant"])} · {h(d["locale"].upper())} · {h(d["article_key"])} · v{d["article_version_number"]}</summary><pre>{h(d["body"])}</pre><small>SHA256: {h(d["body_sha256"])}</small></details>' for d in snap["articles"])
    vals={
      "LANG":lang,"TITLE":h(t["title"]),"OTHER":"index.en.html" if lang=="vi" else "index.vi.html",
      "SWITCH":h(t["switch"]),"WARNING":h(t["warning"]),"NOAUTO":h(t["noauto"]),
      "REVIEWER":h(t["reviewer"]),"TENANT":h(t["tenant"]),"LOCALE":h(t["locale"]),
      "ALL":h(t["all"]),"BOTH":h(t["both"]),"VI":h(t["vi"]),"EN":h(t["en"]),
      "UNFINISHED":h(t["unfinished"]),"IMPORT":h(t["import"]),"DRAFT":h(t["draft"]),
      "NEXT":h(t["next"]),"ATTEST":h(t["attest"]),"FINISH":h(t["finish"]),
      "CARDS":"".join(cards),"CORPUS":h(t["corpus"]),"ARTICLES":articles,
      "FOOTER":h(t["footer"]),"PROGRESS":h(t["progress"]),"META":safe(META),
      "KB":safe({"/".join(k):v for k,v in docs.items()})
    }
    result=TEMPLATE
    for k,v in vals.items():result=result.replace("@@"+k+"@@",v)
    assert "@@" not in result and result.count('<article class="task"')==64 and result.count('<details class="kb"')==12
    assert "localStorage" not in result and "fetch(" not in result and "human_policy_supported" not in result
    target=OUT/f"index.{lang}.html"
    if target.exists():raise RuntimeError("Refusing to overwrite review workbook")
    target.write_text(result)
    print(json.dumps({"status":"FROZEN_BLIND_WORKBOOK_GENERATED","locale":lang,"bytes":target.stat().st_size,"sha256":hashlib.sha256(target.read_bytes()).hexdigest(),"claims":64,"kb_articles":12}))
