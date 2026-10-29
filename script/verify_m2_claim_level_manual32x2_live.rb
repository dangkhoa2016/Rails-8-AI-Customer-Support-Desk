# frozen_string_literal: true
# 32 full questions + 64 human-authored atomic claims. ALL 96 use real
# pinned 4B/4B Modal models. This is a research pilot, never a release gate.
require 'json'
require 'digest'
require 'benchmark'
require 'time'
require 'fileutils'

raise 'synthetic development only' unless Rails.env.development? && ENV['M1_SYNTHETIC_DEMO'] == 'YES'
raise 'explicit 96-query GPU budget required' unless ENV['M2_CLAIM32_LIVE_GPU'] == 'YES' &&
  ENV['M2_CLAIM32_QUERY_BUDGET'] == '96'
root=Rails.root
manifest_path=root.join('review/m2_claim_level_manual32x2_lockbox_20261029.json')
expected_sha='3658b220b04b0cf10ea15ada29a7f734eea16b368574a17a5217c105548bf17f'
raise 'manifest is no longer frozen' unless Digest::SHA256.file(manifest_path).hexdigest==expected_sha
payload=JSON.parse(File.binread(manifest_path))
cases=payload.fetch('cases')
raise 'wrong question count' unless cases.size==32 && cases.sum{|c|c.fetch('claims').size}==64
raise 'unexpected question order' unless cases.map{|c|c.fetch('id')}.uniq.size==32
raise 'wrong approved count' unless KnowledgeArticleVersion.where(status:'approved').count==12 &&
  KnowledgeChunkEmbedding.count==84

# Transparent, nonintrusive wrapper; never logs credentials or user-supplied raw
# questions in output. Counts inference calls and number of document pairs.
class MeteredEmbeddingClient
  attr_reader :model_id,:model_revision,:calls,:seconds
  def initialize
    @inner=ModalEmbeddingClient.new
    @model_id=@inner.model_id
    @model_revision=@inner.model_revision
    @calls=0;@seconds=0.0
  end
  def embed_query(text)
    @calls+=1
    t=Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @inner.embed_query(text)
  ensure
    @seconds+=(Process.clock_gettime(Process::CLOCK_MONOTONIC)-t) if t
  end
end
class MeteredRerankerClient
  attr_reader :model_id,:model_revision,:calls,:document_pairs,:seconds
  def initialize
    @inner=ModalRerankerClient.new
    @model_id=@inner.model_id
    @model_revision=@inner.model_revision
    @calls=0;@document_pairs=0;@seconds=0.0
  end
  def score(query:,documents:)
    @calls+=1;@document_pairs+=documents.size
    t=Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @inner.score(query:query,documents:documents)
  ensure
    @seconds+=(Process.clock_gettime(Process::CLOCK_MONOTONIC)-t) if t
  end
end

gate=KnowledgeRelevanceGate.pilot
scope=KnowledgeAnswerabilityScopeVerifier.pilot
gate.validate!
%w[teamflow-cloud novamart-store].each do |slug|
  scope.validate!(organization:Organization.find_by!(slug:slug),locale:'en')
end
embed=MeteredEmbeddingClient.new
rerank=MeteredRerankerClient.new
counts_before={articles:KnowledgeArticle.count,versions:KnowledgeArticleVersion.count,
 approved:KnowledgeArticleVersion.where(status:'approved').count,
 embeddings:KnowledgeChunkEmbedding.count}
directory=root.join('evidence-m2-claim32x2-20261029')
FileUtils.mkdir_p(directory)
output=directory.join('claim32x2-live.jsonl')
raise 'refusing to overwrite inference evidence' if output.exist?
STDOUT.sync=true
started=Process.clock_gettime(Process::CLOCK_MONOTONIC)
puts "CLAIM32x2_START manifest_sha=#{expected_sha} full_questions=32 atomic_claims=64 serial=1"

File.open(output,'w',0o600) do |io|
  cases.each_with_index do |c,index|
    org=Organization.find_by!(slug:c.fetch('tenant'))
    lang=c.fetch('locale')
    question=c.fetch('question')
    raise 'invalid synthetic full question' unless question.is_a?(String) &&
      question.length.between?(12,300) && question.valid_encoding?
    claims=c.fetch('claims')
    raise 'gold mismatch' unless claims.size==2 &&
      claims.all?{|cl|%w[supported_policy unsupported_in_approved_kb].include?(cl.fetch('gold'))} &&
      claims.all?{|cl|cl.fetch('gold_article_key').nil? == (cl.fetch('gold')=='unsupported_in_approved_kb')}
    time0=Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # Old whole-query combined gate: only for controlled baseline comparison.
    whole=KnowledgeRerankedRetrieval.search(organization:org,role:'agent',query:question,
      locale:lang,embedding_client:embed,reranker_client:rerank,
      candidate_limit:12,limit:5,query_privacy_reviewed:true,
      relevance_gate:gate,answerability_verifier:scope)
    original_seconds=Process.clock_gettime(Process::CLOCK_MONOTONIC)-time0
    ac=claims.map{|item|KnowledgeClaimEvidencePilot::Claim.new(
      id:item.fetch('claim_id'),text:item.fetch('text'))}
    split=KnowledgeClaimEvidencePilot.evaluate(organization:org,role:'agent',locale:lang,
      claims:ac,embedding_client:embed,reranker_client:rerank,
      privacy_reviewed:true,relevance_gate:gate,scope_verifier:scope)
    claim_seconds=Process.clock_gettime(Process::CLOCK_MONOTONIC)-time0-original_seconds
    pairs=split.fetch(:results).zip(claims).map do |observed,gold|
      raise 'case order changed' unless observed.fetch(:claim_id)==gold.fetch('claim_id')
      predicted=observed[:status]=='evidence_candidate_human_review_required'
      expected=gold.fetch('gold')=='supported_policy'
      top1=observed[:citations].first&.fetch(:article_key)
      {
        claim_id:observed[:claim_id],claim_sha256:observed[:claim_sha256],
        gold_support:expected,gold_article:gold['gold_article_key'],
        candidate:predicted,candidate_correct:expected && top1==gold['gold_article_key'],
        candidate_wrong_article:predicted && expected && top1!=gold['gold_article_key'],
        status:observed[:status],raw_top1_article:observed[:raw_top1],
        raw_top1_logit:observed[:raw_top1_logit],
        scope_checked:observed[:scope_checked],
        candidate_article:top1,
        citations:observed[:citations].map{|h|h.slice(:article_key,:citation,:content_sha256,:raw_logit)}
      }
    end
    full_is_supported=claims.all?{|item|item['gold']=='supported_policy'}
    original_ok=whole.any? && whole.first.article_key==claims.first['gold_article_key']
    all_claims_right=pairs.all?{|p|p[:candidate_correct]}
    record={
      id:c.fetch('id'),tenant:org.slug,locale:lang,
      question_sha256:Digest::SHA256.hexdigest(question),
      gold_whole_supported:full_is_supported,
      original_whole_accepted:whole.any?,
      original_top1_article:whole.first&.article_key,
      original_whole_correct:full_is_supported && original_ok,
      manual_claims_all_correct:all_claims_right,
      decomposed_candidate_state:split[:state],
      claim_candidate_count:split[:candidate_count],
      must_be_human_reviewed:true,
      original_seconds:original_seconds.round(3),
      decomposed_seconds:claim_seconds.round(3),
      claims:pairs
    }
    io.puts(JSON.generate(record));io.flush
    puts "CLAIM32x2_CASE #{index+1}/32 #{c.fetch('id')} whole=#{whole.any?} claim=#{split[:state]} gold_whole=#{full_is_supported} secs=#{(original_seconds+claim_seconds).round(2)}"
  end
end
rows=File.readlines(output).map{|line|JSON.parse(line)}
flat=rows.flat_map{|r|r.fetch('claims')}
raise 'incomplete GPU evidence' unless rows.size==32 && flat.size==64
matrix={
 tp:flat.count{|x|x['gold_support'] && x['candidate_correct']},
 fp:flat.count{|x|x['candidate'] && (!x['gold_support'] || x['candidate_wrong_article'])},
 fn:flat.count{|x|x['gold_support'] && !x['candidate_correct']},
 tn:flat.count{|x|!x['gold_support'] && !x['candidate']}
}
baseline={
 full_positive:rows.count{|x|x['gold_whole_supported']},
 full_negative:rows.count{|x|!x['gold_whole_supported']},
 tp:rows.count{|x|x['gold_whole_supported'] && x['original_whole_correct']},
 fp:rows.count{|x|(!x['gold_whole_supported'] && x['original_whole_accepted']) ||
   (x['gold_whole_supported'] && x['original_whole_accepted'] && !x['original_whole_correct'])},
 fn:rows.count{|x|x['gold_whole_supported'] && !x['original_whole_correct']},
 tn:rows.count{|x|!x['gold_whole_supported'] && !x['original_whole_accepted']}
}
whole_decomposed={
 all_supported_accepted:rows.count{|r|r['gold_whole_supported'] && r['manual_claims_all_correct']},
 mixed_with_at_least_one_candidate:rows.count{|r|!r['gold_whole_supported'] && r['claim_candidate_count']==1},
 unsupported_mistakenly_all_accepted:rows.count{|r|!r['gold_whole_supported'] && r['claim_candidate_count']==2},
 supported_with_partial_or_no_candidate:rows.count{|r|r['gold_whole_supported'] && r['claim_candidate_count']!=2}
}
by_stratum={}
rows.group_by{|r|r['tenant']+'/'+r['locale']}.each do |name,subset|
  values=subset.flat_map{|r|r['claims']}
  by_stratum[name]={
    supported:values.count{|x|x['gold_support']},
    supported_candidates_correct:values.count{|x|x['candidate_correct']},
    unsupported:values.count{|x|!x['gold_support']},
    unsupported_candidates:values.count{|x|!x['gold_support'] && x['candidate']},
    partial_composites:subset.count{|r|r['decomposed_candidate_state']=='partial_candidates'}
  }
end
counts_after={articles:KnowledgeArticle.count,versions:KnowledgeArticleVersion.count,
 approved:KnowledgeArticleVersion.where(status:'approved').count,
 embeddings:KnowledgeChunkEmbedding.count}
duration=Process.clock_gettime(Process::CLOCK_MONOTONIC)-started
report={
 kind:'M2_CLAIM_LEVEL_MANUAL_32x2_LIVE_ACCEPTANCE',
 status:'EXPERIMENTAL_COMPLETED_NOT_RELEASE',
 created_utc:Time.now.utc.iso8601,
 manifest_sha256:expected_sha,results_sha256:Digest::SHA256.file(output).hexdigest,
 pinned_models:{
  embedding:[ModalEmbeddingClient::MODEL_ID,ModalEmbeddingClient::MODEL_REVISION],
  reranker:[ModalRerankerClient::MODEL_ID,ModalRerankerClient::MODEL_REVISION]
 },
 full_questions:32,atomic_claims:64,
 decomposer:'HUMAN_AUTHORED_NOT_MODEL',
 human_review_required:true,
 baseline_full_question:baseline,
 atomic_claim_retrieval:matrix,
 by_tenant_locale:by_stratum,
 composite_coverage:whole_decomposed,
 inference_calls:{embedding:embed.calls,reranker:rerank.calls,
    reranker_document_pairs:rerank.document_pairs,
    time_embedding_seconds:embed.seconds.round(3),
    time_reranker_seconds:rerank.seconds.round(3)},
 latency_seconds:{
  total_wall:duration.round(3),
  full_question_total:rows.sum{|r|r['original_seconds']}.round(3),
  decomposition_total:rows.sum{|r|r['decomposed_seconds']}.round(3)
 },
 db_before:counts_before,db_after:counts_after,
 verdict:'NO_AUTONOMOUS_CLAIM_SUPPORT_ASSERTIONS_NO_PREVIEW_ENABLE',
 limitations:'The decompositions and gold labels were written by the developer; retrieval plus prompt contrast cannot prove entailment. Inference cost measured in calls/latency only, not billed dollars.'
}
path=directory.join('claim32x2-report.json')
path.write(JSON.pretty_generate(report)+"\n")
raise 'DB mutation observed' unless counts_before==counts_after
puts 'CLAIM32x2_COMPLETE '+JSON.generate(report)
