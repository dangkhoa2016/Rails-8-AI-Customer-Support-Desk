# frozen_string_literal: true
# READ-ONLY audit of assistant's PROVISIONAL (not human-approved) KB labels.
# This script does NOT infer an NLI result, approve KB, or mutate the database.
require 'json'
require 'digest'
require 'fileutils'
require 'time'
raise 'synthetic development required' unless Rails.env.development? && ENV['M1_SYNTHETIC_DEMO']=='YES'
root=Rails.root
review_file=root.join('review/m2_claim64_assistant_provisional_semantic_audit_20261029.json')
queue_file=root.join('evidence-m2-claim32x2-20261029/claim-level-blind-human-validation.json')
original_file=root.join('review/m2_claim_level_manual32x2_lockbox_20261029.json')
prediction_file=root.join('evidence-m2-claim32x2-20261029/claim32x2-live.jsonl')
review=JSON.parse(File.binread(review_file))
queue=JSON.parse(File.binread(queue_file))
original=JSON.parse(File.binread(original_file))
predictions=File.readlines(prediction_file).map{|line|JSON.parse(line)}
raise 'review is not explicitly provisional' unless
  review.fetch('status')=='PROVISIONAL_NOT_INDEPENDENT_HUMAN_APPROVAL' &&
  review.fetch('items').size==64 && queue.fetch('tasks').size==64
raise 'old lockbox missing' unless Digest::SHA256.file(original_file).hexdigest==
  '3658b220b04b0cf10ea15ada29a7f734eea16b368574a17a5217c105548bf17f'
approved=KnowledgeArticleVersion.where(status:'approved').includes(:knowledge_article,:organization).to_a
raise 'wrong approved corpus count' unless approved.size==12
before={articles:KnowledgeArticle.count,versions:KnowledgeArticleVersion.count,
  approved:approved.size,embeddings:KnowledgeChunkEmbedding.count}
raise 'unexpected DB baseline' unless before=={articles:100,versions:212,approved:12,embeddings:84}
article_map=approved.index_by{|v| [v.organization.slug,v.locale,v.knowledge_article.article_key]}
raise 'duplicate article/locale' unless article_map.size==12
corpus=approved.sort_by{|v|[v.organization.slug,v.locale,v.knowledge_article.article_key]}.map do |v|
  raise 'approved digest corrupted' unless Digest::SHA256.hexdigest(v.body)==v.sha256 &&
    v.active_on?(Date.current)
  {
    tenant:v.organization.slug,locale:v.locale,article_key:v.knowledge_article.article_key,
    article_version_number:v.version_number,
    article_version_id:v.id,policy_version:v.policy_version,
    body_sha256:v.sha256,body:v.body
  }
end
qmap=queue.fetch('tasks').index_by{|v|v.fetch('claim_id')}
pmap=predictions.flat_map{|v|v.fetch('claims')}.index_by{|v|v.fetch('claim_id')}
goldmap=original.fetch('cases').flat_map{|c|c.fetch('claims')}.index_by{|v|v.fetch('claim_id')}
raise 'misaligned IDs across queue, old lockbox, results, audit' unless
  qmap.size==pmap.size && pmap.size==goldmap.size && goldmap.size==64 &&
  review.fetch('items').map{|x|x.fetch('claim_id')}.sort==qmap.keys.sort
categories=%w[policy_supported_affirmative policy_supported_explicit_negative not_documented_in_approved_kb]
rows=review.fetch('items').map do |item|
  id=item.fetch('claim_id')
  row=qmap.fetch(id)
  p=pmap.fetch(id)
  raise 'wrong prediction hash for claim' unless p.fetch('claim_sha256')==Digest::SHA256.hexdigest(row.fetch('atomic_claim'))
  category=item.fetch('category')
  raise 'invalid audit category' unless categories.include?(category)
  if category=='not_documented_in_approved_kb'
    raise 'untrusted absence source' unless item['supporting_article_key'].nil? && item['policy_reference'].nil?
    target=nil
  else
    target=article_map.fetch([row.fetch('tenant'),row.fetch('locale'),item.fetch('supporting_article_key')])
    ref=item['policy_reference']
    raise 'unrecognized policy evidence ref' unless ref.nil? || target.body.include?(ref)
    raise 'non-v2 supported article' unless target.version_number==2
  end
  {
    claim_id:id,tenant:row.fetch('tenant'),locale:row.fetch('locale'),
    question_sha256:Digest::SHA256.hexdigest(row.fetch('parent_question')),
    claim_sha256:Digest::SHA256.hexdigest(row.fetch('atomic_claim')),
    assistant_provisional_label:category,
    policy_reference:item['policy_reference'],
    policy_evidence_locator:item.fetch('evidence_locator'),
    cited_approved_article:target&.knowledge_article&.article_key,
    cited_approved_version_id:target&.id,
    cited_approved_version_number:target&.version_number,
    cited_body_sha256:target&.sha256,
    previous_developer_gold:goldmap.fetch(id)['gold'],
    previous_candidate:p.fetch('candidate'),
    previous_candidate_article:p['candidate_article'],
    changed_supportedness_vs_developer_gold:
      ((category!='not_documented_in_approved_kb') != (goldmap.fetch(id)['gold']=='supported_policy')),
    requires_external_human_review:true
  }
end
totals=categories.to_h{|c|[c,rows.count{|x|x[:assistant_provisional_label]==c}]}
changed=rows.select{|x|x[:changed_supportedness_vs_developer_gold]}
total_supported=rows.count{|x|x[:assistant_provisional_label]!='not_documented_in_approved_kb'}
tp=rows.count{|x|x[:assistant_provisional_label]!='not_documented_in_approved_kb' &&
  x[:previous_candidate] && x[:previous_candidate_article]==x[:cited_approved_article]}
fp=rows.count{|x|x[:assistant_provisional_label]=='not_documented_in_approved_kb' && x[:previous_candidate]}
fn=total_supported-tp
tn=rows.size-total_supported-fp
after={articles:KnowledgeArticle.count,versions:KnowledgeArticleVersion.count,
 approved:KnowledgeArticleVersion.where(status:'approved').count,embeddings:KnowledgeChunkEmbedding.count}
raise 'DB CHANGED during audit' unless before==after
outdir=root.join('evidence-m2-claim64-provisional-audit-20261029')
FileUtils.mkdir_p(outdir)
snapshot=outdir.join('approved-kb-v2-readonly-snapshot.json')
comparison=outdir.join('assistant-provisional-claim-comparison.json')
raise 'refuse overwrite evidence' if snapshot.exist? || comparison.exist?
snapshot.write(JSON.pretty_generate({
  kind:'M2_APPROVED_KB_V2_SYNTHETIC_READONLY_SNAPSHOT',
  captured_utc:Time.now.utc.iso8601,
  article_count:corpus.size,articles:corpus
})+"\n")
comparison.write(JSON.pretty_generate({
  kind:'M2_64_CLAIM_SECOND_PASS_ASSISTANT_REVIEW',
  status:'PROVISIONAL_AI_NOT_INDEPENDENT_HUMAN_ADJUDICATION',
  captured_utc:Time.now.utc.iso8601,
  provisional_audit_sha256:Digest::SHA256.file(review_file).hexdigest,
  approved_corpus_snapshot_sha256:Digest::SHA256.file(snapshot).hexdigest,
  blind_queue_sha256:Digest::SHA256.file(queue_file).hexdigest,
  original_gold_manifest_sha256:Digest::SHA256.file(original_file).hexdigest,
  original_gpu_results_sha256:Digest::SHA256.file(prediction_file).hexdigest,
  category_counts:totals,developer_gold_disagreements:changed.map{|v|v[:claim_id]},
  corrected_diagnostic_not_independent_benchmark:{tp:tp,fp:fp,fn:fn,tn:tn,
   supported:total_supported,unsupported:64-total_supported},
  before_db:before,after_db:after,
  warning:'Second-pass AI-assisted labeling after observing prior results; not unbiased, not external human review, cannot be counted as a new blind test. Explicit policy NO differs from no documented policy.',
  claims:rows
})+"\n")
puts JSON.generate({status:'PROVISIONAL_AUDIT_CREATED_NOT_HUMAN_APPROVAL',
 approved_corpus_count:corpus.size,
 audit_sha256:Digest::SHA256.file(review_file).hexdigest,
 snapshot_sha256:Digest::SHA256.file(snapshot).hexdigest,
 comparison_sha256:Digest::SHA256.file(comparison).hexdigest,
 category_counts:totals,
 changed_original_gold_ids:changed.map{|v|v[:claim_id]},
 diagnostic_only:{tp:tp,fp:fp,fn:fn,tn:tn},
 db_before:before,db_after:after})
