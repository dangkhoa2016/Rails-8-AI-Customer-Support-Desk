#!/usr/bin/env python3
"""Creates a human-review worksheet without approving any KB article."""
import csv, json
from pathlib import Path
root=Path(__file__).resolve().parent.parent
source=json.loads((root/'data/m2/knowledge_drafts.json').read_text())
out=root/'review/m2_editorial_review_manifest.csv';out.parent.mkdir(parents=True,exist_ok=True)
with out.open('w',newline='',encoding='utf-8-sig') as f:
 w=csv.DictWriter(f,fieldnames=['organization','article_id','locale','title','policy_ids','audience','content_sha256','status','review_decision','reviewer_notes'])
 w.writeheader()
 for a in source['articles']:
  for v in a['versions']:
   w.writerow({'organization':a['organization_slug'],'article_id':a['article_key'],'locale':v['locale'],
    'title':v['title'],'policy_ids':';'.join(a['policy_refs']),'audience':a['audience'],
    'content_sha256':v['sha256'],'status':'draft','review_decision':'','reviewer_notes':''})
print(out)
