#!/usr/bin/env python3
"""One bounded synthetic HTTPS M5.2 acceptance, no business mutations or secret logs."""
import hashlib, json, os, re, time
from pathlib import Path
from urllib.parse import urlparse, parse_qs, urljoin
import requests
from bs4 import BeautifulSoup

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'evidence-m52-background-20261030'
OUT.mkdir(parents=True,exist_ok=True)
LOG=OUT/'https-m52-one-case.json'
assert not LOG.exists(), 'Evidence exists, never overwrite'
password=os.environ['RAILS_PRIVATE_PREVIEW_PASSWORD']
assert len(password)>30
tunnel=Path('/tmp/rails8_m5_cloudflared_20261030.log').read_text()
origin='https://'+re.findall(r'https://([a-z0-9-]+\.trycloudflare\.com)',tunnel)[-1]
case=next(c for c in json.loads((ROOT/'review/m2_dual_qwen3_4b_pilot_queries.json').read_text())['cases']
          if c['case_id']=='M2-4B-01')
s=requests.Session()
first=s.get(origin+'/__private_preview/sign_in',timeout=20)
assert first.status_code==200
nonce=re.search(r'name="nonce"\s+value="([^"]+)"',first.text).group(1)
entered=s.post(origin+'/__private_preview/sign_in',data={'nonce':nonce,'preview_password':password},
               allow_redirects=False,timeout=20)
assert entered.status_code==303
page=s.get(origin+'/demo/sign_in',timeout=20)
soup=BeautifulSoup(page.text,'html.parser')
option=next(o for o in soup.select('optgroup[label="TeamFlow Cloud"] option') if o.text.strip().startswith('Owner ·'))
csrf=soup.select_one('meta[name="csrf-token"]')['content']
auth=s.post(origin+'/demo/sign_in',data={'membership_id':option['value'],'locale':'vi',
              'authenticity_token':csrf},headers={'X-CSRF-Token':csrf},allow_redirects=False,timeout=20)
assert auth.status_code==303
form=s.get(origin+'/kb/ai-search',timeout=20)
assert form.status_code==200
doc=BeautifulSoup(form.text,'html.parser')
assert doc.select_one('textarea[name=query]') and not doc.select_one('textarea[name=query]').has_attr('disabled')
csrf=doc.select_one('meta[name="csrf-token"]')['content']
started=time.monotonic()
submitted=s.post(origin+'/kb/ai-search',
  data={'query':case['query'],'privacy_confirmed':'1','authenticity_token':csrf},
  headers={'X-CSRF-Token':csrf,'Accept':'text/html'},allow_redirects=False,timeout=40)
queue_ms=round((time.monotonic()-started)*1000,1)
assert submitted.status_code==303, f'POST expected 303, got {submitted.status_code}'
assert queue_ms<15000, f'POST took too long: {queue_ms}ms'
location=urljoin(origin,submitted.headers.get('Location',''))
assert urlparse(location).hostname==urlparse(origin).hostname
run_id=parse_qs(urlparse(location).query).get('run',[''])[0]
assert re.fullmatch(r'[0-9a-f-]{36}',run_id), 'invalid random public ID'
run_url=origin+'/kb/ai-search/runs/'+run_id
result={'kind':'M52_REAL_HTTPS_POSTGRES_SOLID_QUEUE_ONE_CASE','case_id':case['case_id'],
        'query_sha256':hashlib.sha256(case['query'].encode()).hexdigest(),
        'tenant':case['tenant'],'locale':case['locale'],'enqueue_status':submitted.status_code,
        'enqueue_ms':queue_ms,'async_completed':False,'sealed80':'BLOCKED',
        'business_writes':0,'model_calls_from_https':1}
print(json.dumps({'event':'queued','case_id':case['case_id'],'enqueue_ms':queue_ms,'http':303}),flush=True)
deadline=time.monotonic()+560
polls=0
while time.monotonic()<deadline:
    time.sleep(3)
    response=s.get(run_url,headers={'Turbo-Frame':'ai_search_run_'+run_id},timeout=25)
    assert response.status_code==200,f'status GET: {response.status_code}'
    status=BeautifulSoup(response.text,'html.parser')
    frame=status.select_one('turbo-frame#ai_search_run_'+run_id)
    assert frame is not None
    state=frame.get('data-state')
    polls+=1
    if state=='succeeded':
        hits=status.select('article.ai-hit')
        keys=[h.select_one('.ai-hit-top strong a').text.strip() for h in hits]
        assert keys and keys[0]=='TF-KB-012'
        assert all(k.startswith('TF-') for k in keys)
        assert all('SHA256' in h.get_text(' ',strip=True) for h in hits)
        result.update(async_completed=True,final_state=state,citations=len(hits),
           top1=keys[0],polls=polls,end_to_end_ms=round((time.monotonic()-started)*1000,1),
           status='PASS_REAL_HTTPS_POSTGRES_BACKGROUND_INFERENCE')
        break
    if state=='failed':
        result.update(final_state='failed',polls=polls,status='FAIL_JOB')
        break
else:
    result.update(final_state='timeout',polls=polls,status='FAIL_POLL_TIMEOUT')
LOG.write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n')
print(json.dumps({k:v for k,v in result.items() if k in
                   ('status','enqueue_ms','end_to_end_ms','top1','citations','polls','final_state')}),flush=True)
if not result['async_completed']:raise RuntimeError('AI did not complete in bounded time; see sanitized evidence')
