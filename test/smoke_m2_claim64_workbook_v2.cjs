// Local browser smoke test. Synthetic in-browser fixtures are NOT reviewer decisions.
const puppeteer=require("puppeteer"),fs=require("fs"),crypto=require("crypto");
(async()=>{
 const b=await puppeteer.launch({headless:true,args:["--no-sandbox","--disable-dev-shm-usage"]});
 const root="/content/Rails-8-AI-Customer-Support-Desk";
 const q=JSON.parse(fs.readFileSync(root+"/evidence-m2-claim32x2-20261029/claim-level-blind-human-validation.json"));
 const snap=fs.readFileSync(root+"/evidence-m2-claim64-provisional-audit-20261029/approved-kb-v2-readonly-snapshot.json");
 for(const lang of ["vi","en"]){
  const page=await b.newPage(),requests=[];
  page.on("request",r=>{if(!r.url().startsWith("file:"))requests.push(r.url())});
  page.on("dialog",async d=>d.accept());
  await page.goto("file://"+root+"/evidence-m2-claim64-independent-review-v2-20261029/index."+lang+".html");
  const baseline=await page.evaluate(()=>[document.querySelectorAll("article.task").length,document.querySelectorAll("details.kb").length,document.querySelector("#finish").disabled]);
  if(baseline.join(",")!=="64,12,true")throw Error("BASELINE_FAILED "+lang+" "+baseline);
  const tmp="/tmp/FAKE_DRAFT_FOR_BROWSER_"+lang+".json";
  fs.writeFileSync(tmp,JSON.stringify({
    source_manifest_sha256:q.source_manifest_sha256,candidate_evidence_sha256:q.model_evidence_sha256,
    approved_snapshot_sha256:crypto.createHash("sha256").update(snap).digest("hex"),
    reviewer_id:"SYNTHETIC_BROWSER_TEST_NOT_HUMAN",
    total:64,completion:1,decisions:q.tasks.map((x,i)=>({
       claim_id:x.claim_id,tenant:x.tenant,locale:x.locale,
       reviewer_decision:i===0?"not_documented":null,evidence_article:null,evidence_quote_or_section:"",
       reviewer_notes:i===0?"SYNTHETIC TEST ONLY: no actual human policy review.":""}))}));
  await (await page.$("#import")).uploadFile(tmp);
  await page.waitForFunction(()=>document.querySelector("#reviewer").value==="SYNTHETIC_BROWSER_TEST_NOT_HUMAN",{timeout:7500});
  const imported=await page.evaluate(()=>[
    document.querySelector("article.task .verdict").value,
    document.querySelector("#finish").disabled,
    document.querySelector("#attest").checked,
    document.querySelector("#progress").textContent.includes("1/64")]);
  if(imported.join(",")!=="not_documented,true,false,true")throw Error("IMPORT_FAILED "+lang+" "+imported);
  const finished=await page.evaluate(()=>{
   for(const c of document.querySelectorAll("article.task")){
     c.querySelector(".verdict").value="not_documented";
     c.querySelector(".article").value="";
     c.querySelector(".notes").value="SYNTHETIC FAKE LABEL FOR BROWSER TEST ONLY.";
   }
   document.querySelector("article.task .verdict").dispatchEvent(new Event("input",{bubbles:true}));
   const blockedBefore=document.querySelector("#finish").disabled;
   document.querySelector("#attest").checked=true;
   document.querySelector("#attest").dispatchEvent(new Event("input",{bubbles:true}));
   return [blockedBefore,document.querySelector("#finish").disabled,
       document.querySelector("#progress").textContent.includes("64/64")];
  });
  if(finished.join(",")!=="true,false,true")throw Error("COMPLETE_GUARD_FAILED "+lang+" "+finished);
  if(requests.length)throw Error("EXTERNAL_REQUEST "+lang+" "+requests);
  console.log("BROWSER_PASS",lang,"cards 64 KB 12 import PASS guard PASS no_network PASS");
  await page.close();
 }
 await b.close();console.log("BILINGUAL_OFFLINE_BROWSER_SMOKE_PASS");
})().catch(e=>{console.error(e.stack||String(e));process.exit(2)});
