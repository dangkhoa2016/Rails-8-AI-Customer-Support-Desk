#!/usr/bin/env python3
"""Two HUMAN reviewer exports: structural agreement only; never auto-release."""
import argparse,hashlib,json,sys
from collections import Counter,defaultdict
from pathlib import Path
from validate_m2_external_review_export import check_file

LABELS=("affirmative_policy","explicit_negative_policy","not_documented")
EXPECTED_STATUS="COMPLETE_SELF_ATTESTED_UNVERIFIED"
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def load(p):
    result=check_file(p)
    assert not result["pending"] and not result["uncertain"],"Pending/uncertain decisions need human review"
    obj=json.loads(p.read_text())
    assert obj["review_status"]==EXPECTED_STATUS,"Draft is not a complete review"
    assert obj.get("self_attested_independent_review") is True,"Missing self-attestation"
    assert obj.get("total")==obj.get("completion")==64,"Incorrect completed counts"
    claims={d["claim_id"]:d for d in obj["decisions"]}
    assert len(claims)==64
    assert all(d["reviewer_decision"] in LABELS for d in claims.values())
    return obj,claims
def compare(first,second):
    assert first.resolve()!=second.resolve(),"Same path cannot be two independent reviews"
    a,ac=load(first)
    b,bc=load(second)
    assert a["reviewer_id"].strip()!=b["reviewer_id"].strip(),"Reviewer IDs must differ"
    assert all(a[k]==b[k] for k in
      ("source_manifest_sha256","candidate_evidence_sha256","approved_snapshot_sha256")),"Inconsistent frozen source"
    assert set(ac)==set(bc),"Mismatched claim set"
    matrix={k:{v:0 for v in LABELS} for k in LABELS}
    strata=defaultdict(lambda:{"total":0,"agreed":0})
    issues=[]
    agree=0
    for ident in sorted(ac):
        left,right=ac[ident],bc[ident]
        x,y=left["reviewer_decision"],right["reviewer_decision"]
        matrix[x][y]+=1
        g=left["tenant"]+"/"+left["locale"]
        strata[g]["total"]+=1
        if x==y:agree+=1;strata[g]["agreed"]+=1
        cite_different=x==y and x!="not_documented" and left["evidence_article"]!=right["evidence_article"]
        if x!=y or cite_different:
            issues.append({"claim_id":ident,"tenant":left["tenant"],"locale":left["locale"],
                "first_label":x,"second_label":y,
                "first_article":left["evidence_article"],"second_article":right["evidence_article"],
                "reason":"LABEL_DISAGREEMENT" if x!=y else "CITATION_ARTICLE_DISAGREEMENT"})
    n=len(ac)
    rows=Counter({k:sum(matrix[k].values()) for k in LABELS})
    cols=Counter({k:sum(matrix[v][k] for v in LABELS) for k in LABELS})
    pe=sum(rows[k]*cols[k] for k in LABELS)/n**2
    kappa=(agree/n-pe)/(1-pe) if pe<1 else None
    return {
       "kind":"CLAIM64_TWO_SELF_ATTESTED_HUMAN_EXPORTS_DIAGNOSTIC",
       "status":"STRUCTURAL_AGREEMENT_ONLY_NOT_SEMANTIC_CERTIFICATION",
       "first_sha256":digest(first),"second_sha256":digest(second),
       "first_reviewer_self_reported":a["reviewer_id"],
       "second_reviewer_self_reported":b["reviewer_id"],
       "verified_identity":False,"verified_independence":False,
       "claims":n,"agreement_count":agree,"agreement_rate":round(agree/n,6),
       "cohens_kappa_diagnostic":None if kappa is None else round(kappa,6),
       "first_rows_second_columns":matrix,"by_tenant_locale":dict(sorted(strata.items())),
       "arbitration_required":issues,"arbitration_issue_count":len(issues),
       "human_semantic_correctness":"NOT_VERIFIED",
       "human_signoff":"NOT_PROVIDED",
       "automatic_release":False,"claim_level_release":"BLOCKED",
       "note":"Two matching reviewers do not establish independence, semantic correctness, policy entailment or production readiness."}
if __name__=="__main__":
    p=argparse.ArgumentParser()
    p.add_argument("first_review",type=Path);p.add_argument("second_review",type=Path)
    p.add_argument("--output",type=Path)
    args=p.parse_args()
    try:
        output=compare(args.first_review,args.second_review)
        text=json.dumps(output,ensure_ascii=False,indent=2)+"\n"
        if args.output:
            assert not args.output.exists(),"Do not overwrite old evidence"
            args.output.write_text(text)
        print(text,end="")
    except (KeyError,ValueError,TypeError,AssertionError,FileNotFoundError) as e:
        print(json.dumps({"status":"REVIEW_EXPORT_INVALID_OR_UNRESOLVED","error":str(e)[:180],"release":"BLOCKED"}))
        sys.exit(2)
