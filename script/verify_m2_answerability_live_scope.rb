# frozen_string_literal: true
# Real Qwen3 Embedding/Reranker 4B acceptance of experimental scope gate.
# Read-only synthetic DB. Strongly bounded GPU calls. Do not use real customer text.
require 'json'
require 'digest'
require 'time'
require 'benchmark'
require 'fileutils'
raise 'synthetic development only' unless Rails.env.development? && ENV['M1_SYNTHETIC_DEMO']=='YES'
raise 'explicit bounded GPU run required' unless ENV['M2_SCOPE_LIVE_GPU']=='YES'
root=Rails.root
f=JSON.parse(root.join('review/m2_answerability_multi_intent_lockbox_20261029.json').read)
cases=f.fetch('cases').index_by {|x|x.fetch('id')}
selected=%w[AX10 AX11 AX19 AX21]
original_query='Hóa đơn đã thanh toán nhưng gói chưa kích hoạt thì kiểm tra điều gì?'
gate=KnowledgeRelevanceGate.pilot
scope=KnowledgeAnswerabilityScopeVerifier.pilot
before={
 articles:KnowledgeArticle.count,versions:KnowledgeArticleVersion.count,
 approved:KnowledgeArticleVersion.where(status:'approved').count,
 embeddings:KnowledgeChunkEmbedding.count
}
embed=ModalEmbeddingClient.new
rerank=ModalRerankerClient.new
evaluations=selected.map{|id|cases.fetch(id)}
evaluations << {'id'=>'ORIGINAL-NM-WRONG-TENANT','tenant'=>'novamart-store','locale'=>'vi',
 'expected_article_key'=>nil,'query'=>original_query}
results=[]
evaluations.each do |test|
  org=Organization.find_by!(slug:test.fetch('tenant'))
  answer=nil
  elapsed=Benchmark.realtime do
    answer=KnowledgeRerankedRetrieval.search(
      organization:org,role:'agent',query:test.fetch('query'),
      locale:test.fetch('locale'),embedding_client:embed,reranker_client:rerank,
      relevance_gate:gate, answerability_verifier:scope,
      candidate_limit:12,limit:5,query_privacy_reviewed:true
    )
  end
  expect=test['expected_article_key']
  pass=expect.nil? ? answer.empty? : answer.first&.article_key==expect
  results << {
    id:test.fetch('id'),tenant:org.slug,locale:test.fetch('locale'),
    query_sha256:Digest::SHA256.hexdigest(test.fetch('query')),
    expected_article:expect,pass:pass,qualified_count:answer.length,
    top1:answer.first&.article_key,citations:answer.map(&:citation),
    content_sha256:answer.map(&:sha256),elapsed_seconds:elapsed.round(3)
  }
end
after={
 articles:KnowledgeArticle.count,versions:KnowledgeArticleVersion.count,
 approved:KnowledgeArticleVersion.where(status:'approved').count,
 embeddings:KnowledgeChunkEmbedding.count
}
report={
 status:results.all? {|r|r[:pass]} && before==after ? 'PASS' : 'FAIL',
 captured_utc:Time.now.utc.iso8601,
 model_ids:[ModalEmbeddingClient::MODEL_ID,ModalRerankerClient::MODEL_ID],
 model_revisions:[ModalEmbeddingClient::MODEL_REVISION,ModalRerankerClient::MODEL_REVISION],
 policy_sha256:Digest::SHA256.file(root.join(KnowledgeAnswerabilityScopeVerifier::POLICY_FILE)).hexdigest,
 fixture_sha256:Digest::SHA256.file(root.join('review/m2_answerability_multi_intent_lockbox_20261029.json')).hexdigest,
 queries:results.size,parallel_instances:1,random_sampling:false,
 before:before,after:after,results:results
}
out=root.join('evidence-m2-answerability-20261029/live-scope-acceptance.json')
raise 'refusing to overwrite live evidence' if out.exist?
out.write(JSON.pretty_generate(report)+"\n")
puts JSON.pretty_generate(report)
raise 'live scope verification failed' unless report[:status]=='PASS'
