# frozen_string_literal: true
# Sealed, predeclared, read-only GPU challenge. Do not change pilot thresholds after
# seeing this lockbox's scores. Outputs hashes/citations, never customer data.
require 'json'
require 'digest'
require 'time'
require 'benchmark'
require 'fileutils'

raise 'synthetic development runtime required' unless Rails.env.development? && ENV['M1_SYNTHETIC_DEMO'] == 'YES'
raise 'explicit fixed GPU budget required' unless ENV['M2_SEALED80_LIVE_GPU'] == 'YES'
path = Rails.root.join('review/m2_scope_sealed_challenge80_20261029.json')
manifest_bytes = File.binread(path)
expected_manifest_hash = '13ab3412404239a6bc3232ca1598cb12b00db1bf29f5d6226ae3a4d9f88ed20a'
raise 'lockbox manifest changed' unless Digest::SHA256.hexdigest(manifest_bytes) == expected_manifest_hash
data = JSON.parse(manifest_bytes)
cases = data.fetch('cases')
raise 'invalid lockbox count' unless data.fetch('id') == 'M2_SCOPE_80_SEALED_CHALLENGE_V1' &&
  cases.size == 80 && cases.map { |c| c.fetch('id') }.uniq.size == 80
raise 'gpu budget must be exactly 80' unless Integer(ENV.fetch('M2_SEALED80_CASE_BUDGET','80')) == 80
gate = KnowledgeRelevanceGate.pilot
scope = KnowledgeAnswerabilityScopeVerifier.pilot
gate.validate!
%w[teamflow-cloud novamart-store].each do |slug|
  scope.validate!(organization:Organization.find_by!(slug:slug),locale:'en')
end

out_dir = Rails.root.join('evidence-m2-sealed80-20261029')
FileUtils.mkdir_p(out_dir)
out = out_dir.join('sealed80-live-results.jsonl')
raise 'refuse to overwrite prior sealed evidence' if out.exist?
models={embedding: ModalEmbeddingClient::MODEL_ID,
        embedding_revision: ModalEmbeddingClient::MODEL_REVISION,
        reranker: ModalRerankerClient::MODEL_ID,
        reranker_revision: ModalRerankerClient::MODEL_REVISION}
before={articles:KnowledgeArticle.count,
        versions:KnowledgeArticleVersion.count,
        approved:KnowledgeArticleVersion.where(status:'approved').count,
        embeddings:KnowledgeChunkEmbedding.count}
embed=ModalEmbeddingClient.new
rerank=ModalRerankerClient.new
STDOUT.sync=true
puts "SEALED80_START manifest=#{expected_manifest_hash} cases=#{cases.size} serial=1"
started=Process.clock_gettime(Process::CLOCK_MONOTONIC)
timings=[]
File.open(out,'w',0o600) do |io|
  cases.each_with_index do |item,index|
    query=item.fetch('query')
    raise 'unexpected query size/encoding' unless query.is_a?(String) &&
      query.valid_encoding? && query.length.between?(12,300)
    org=Organization.find_by!(slug:item.fetch('tenant'))
    locale=item.fetch('locale')
    raise 'invalid locale' unless %w[vi en].include?(locale)
    raise 'invalid gold' unless (item['expected_article_key'].nil?) == (item['kind'] != 'supported')
    hits=nil
    t0=Process.clock_gettime(Process::CLOCK_MONOTONIC)
    hits=KnowledgeRerankedRetrieval.search(organization:org,role:'agent',query:query,
      locale:locale,embedding_client:embed,reranker_client:rerank,
      candidate_limit:12,limit:12,query_privacy_reviewed:true)
    qualified=gate.filter(hits).first(5)
    pre_scope_at=Process.clock_gettime(Process::CLOCK_MONOTONIC)
    scope_pass=qualified.any? && scope.supports?(
      query:query,hit:qualified.first,locale:locale,
      organization:org,reranker_client:rerank)
    accepted=scope_pass ? qualified.select{|h|h.article_key==qualified.first.article_key}.first(5) : []
    elapsed=(Process.clock_gettime(Process::CLOCK_MONOTONIC)-t0).round(3)
    scope_elapsed=(Process.clock_gettime(Process::CLOCK_MONOTONIC)-pre_scope_at).round(3)
    gold=item['expected_article_key']
    base_correct=gold.nil? ? qualified.empty? : qualified.first&.article_key==gold
    combined_correct=gold.nil? ? accepted.empty? : accepted.first&.article_key==gold
    record={
      id:item.fetch('id'),tenant:org.slug,locale:locale,
      kind:item.fetch('kind'),gold_article:gold,query_sha256:Digest::SHA256.hexdigest(query),
      raw_top1_article:hits.first&.article_key,raw_top1_logit:hits.first&.rerank_score,
      baseline_top1_article:qualified.first&.article_key,
      baseline_accepted:qualified.any?,baseline_correct:base_correct,
      scope_checked:qualified.any?,scope_passed:!!scope_pass,
      combined_accepted:accepted.any?,combined_top1_article:accepted.first&.article_key,
      combined_correct:combined_correct,qualified_citations:accepted.map(&:citation),
      qualified_content_sha256:accepted.map(&:sha256),
      elapsed_seconds:elapsed,scope_seconds:scope_elapsed
    }
    io.puts(JSON.generate(record));io.flush
    timings << elapsed
    puts "SEALED80_CASE #{index+1}/80 #{record[:id]} label=#{gold.nil? ? 'UNSUPPORTED' : 'SUPPORTED'} base=#{record[:baseline_accepted]} combined=#{record[:combined_accepted]} correct=#{combined_correct} elapsed_s=#{elapsed}"
  end
end
results=File.readlines(out).map{|s|JSON.parse(s)}
assert_counts=lambda do |mode|
  tp=results.count{|r|r['gold_article'] && r["#{mode}_accepted"] && r["#{mode}_correct"]}
  fn=results.count{|r|r['gold_article'] && !r["#{mode}_correct"]}
  # Any accepted unsupported response or accepted wrong-article response is unsafe.
  fp=results.count{|r|(!r['gold_article'] && r["#{mode}_accepted"]) ||
    (r['gold_article'] && r["#{mode}_accepted"] && !r["#{mode}_correct"])}
  tn=results.count{|r|!r['gold_article'] && !r["#{mode}_accepted"]}
  {tp:tp,fp:fp,fn:fn,tn:tn}
end
baseline=assert_counts.call('baseline')
combined=assert_counts.call('combined')
by_stratum={}
results.group_by{|r|[r['tenant'],r['locale']]}.each do |k,subset|
  metrics={}
  %w[baseline combined].each do |mode|
    metrics[mode]={
      supported_correct:subset.count{|r|r['gold_article'] && r["#{mode}_correct"]},
      supported_total:subset.count{|r|r['gold_article']},
      unsupported_accepted:subset.count{|r|r['gold_article'].nil? && r["#{mode}_accepted"]},
      unsupported_total:subset.count{|r|r['gold_article'].nil?}
    }
  end
  by_stratum[k.join('/')]=metrics
end
after={articles:KnowledgeArticle.count,versions:KnowledgeArticleVersion.count,
       approved:KnowledgeArticleVersion.where(status:'approved').count,
       embeddings:KnowledgeChunkEmbedding.count}
decision=(combined[:fp]==0 && combined[:tp]>=16 && before==after &&
          results.size==80) ? 'ELIGIBLE_FOR_ISOLATED_PREVIEW_SMOKE' : 'BLOCK_PREVIEW_FLAG'
report={
 kind:'M2_SCOPE_SEALED80_ACCEPTANCE',status:'COMPLETED',
 captured_utc:Time.now.utc.iso8601,
 sealed_manifest_sha256:expected_manifest_hash,
 model_pins:models,
 policy_sha256:Digest::SHA256.file(Rails.root.join(KnowledgeAnswerabilityScopeVerifier::POLICY_FILE)).hexdigest,
 results_sha256:Digest::SHA256.file(out).hexdigest,
 synthetic_queries:80,seed:'NO_RNG_MANUALLY_AUTHORED',parallel_instances:1,
 baseline:baseline,combined:combined,per_tenant_locale:by_stratum,
 supported_recall:combined[:tp]/20.0,
 false_positive_count:combined[:fp],
 adjudication_rule:data.fetch('lockbox_rules'),
 decision:decision,
 latency_seconds:{total:(Process.clock_gettime(Process::CLOCK_MONOTONIC)-started).round(2),
                    min:timings.min,max:timings.max,
                    mean:(timings.sum/timings.size).round(3)},
 db_before:before,db_after:after,
 caveat:'Only 80 synthetic pre-labeled questions; topical probe contrast is not proof of entailment. No production claims.'
}
report_path=out_dir.join('sealed80-acceptance.json')
report_path.write(JSON.pretty_generate(report)+"\n")
puts "SEALED80_COMPLETE #{JSON.generate(report)}"
