// Bilingual read-only sample approval UI browser smoke; no model or policy judgments.
const puppeteer=require("puppeteer");
(async()=>{
 const browser=await puppeteer.launch({headless:true,args:["--no-sandbox","--disable-dev-shm-usage"]});
 const root="/content/Rails-8-AI-Customer-Support-Desk/evidence-m2-claim64-independent-review-v2-20261029/";
 try{
  for(const lang of ["vi","en"]){
   const page=await browser.newPage(),external=[];
   page.on("request",r=>{if(!r.url().startsWith("file:"))external.push(r.url());});
   await page.goto("file://"+root+"sample-approval."+lang+".html",{waitUntil:"load"});
   const state=await page.evaluate(()=>{
     const claims=[...document.querySelectorAll(".sample-claim")];
     const all=claims.length;
     const kb=document.querySelectorAll(".kb article").length;
     const count=document.querySelector("#count").textContent;
     const t=document.querySelector("#tenant"),l=document.querySelector("#locale");
     t.value="teamflow-cloud";t.dispatchEvent(new Event("change",{bubbles:true}));
     const team=claims.filter(c=>!c.hidden).length;
     l.value="vi";l.dispatchEvent(new Event("change",{bubbles:true}));
     const tf_vi=claims.filter(c=>!c.hidden).length;
     t.value="novamart-store";t.dispatchEvent(new Event("change",{bubbles:true}));
     const nova_vi=claims.filter(c=>!c.hidden).length;
     t.value="";l.value="";l.dispatchEvent(new Event("change",{bubbles:true}));
     const reset=claims.filter(c=>!c.hidden).length;
     return {all,kb,count,team,tf_vi,nova_vi,reset,
       text:document.body.textContent.slice(0,1000),
       title:document.title};
   });
   if(state.all!==64||state.kb!==12||state.team!==32||state.tf_vi!==16||state.nova_vi!==16||state.reset!==64||external.length)
      throw Error("SAMPLE_BROWSER_FAIL "+lang+" "+JSON.stringify(state));
   if(!state.text.includes("64 / 64")||!state.text.includes("12 / 12"))
      throw Error("INVALID_SAMPLE_COUNTS "+lang);
   console.log("SAMPLE_DEMO_BROWSER_PASS",lang,"64 claims 12 KB filters 32/16/16/64 no_external_network");
   await page.close();
  }
  console.log("SAMPLE_APPROVAL_BILINGUAL_BROWSER_PASS");
 }finally{await browser.close();}
})().catch(e=>{console.error(e.stack||String(e));process.exit(2)});
