# frozen_string_literal: true
# Targeted live GPU acceptance on the existing (not reseeded) synthetic DB.
require 'json'
require 'digest'
require 'time'
require 'benchmark'

raise 'synthetic development only' unless Rails.env.development? && ENV['M1_SYNTHETIC_DEMO'] == 'YES'
raise 'explicit GPU approval' unless ENV['M2_GATE_LIVE_ACCEPT'] == 'YES'
before = {articles: KnowledgeArticle.count, versions: KnowledgeArticleVersion.count,
          approved: KnowledgeArticleVersion.where(status: 'approved').count,
          embeddings: KnowledgeChunkEmbedding.count}
gate = KnowledgeRelevanceGate.pilot
gate.validate!
query = 'Hóa đơn đã thanh toán nhưng gói chưa kích hoạt thì kiểm tra điều gì?'
cases = [
  ['novamart-store', 'vi', nil, query],
  ['teamflow-cloud', 'vi', 'TF-KB-012', query],
  ['novamart-store', 'vi', 'NM-KB-014', 'Đơn hàng sau giảm giá 500.000 đồng có được miễn phí vận chuyển thường không?']
]
embed = ModalEmbeddingClient.new
rerank = ModalRerankerClient.new
results = cases.map do |tenant, locale, expected, sentence|
  org = Organization.find_by!(slug: tenant)
  hits = nil
  elapsed = Benchmark.realtime do
    hits = KnowledgeRerankedRetrieval.search(organization: org, role: 'agent',
      query: sentence, locale: locale, embedding_client: embed, reranker_client: rerank,
      query_privacy_reviewed: true, candidate_limit: 12, limit: 5,
      relevance_gate: gate)
  end
  pass = expected ? hits.first&.article_key == expected : hits.empty?
  {
    tenant: tenant, locale: locale, expected_article: expected,
    no_evidence_expected: expected.nil?, result_count: hits.size,
    top1: hits.first&.article_key, citations: hits.map(&:citation),
    sha256: hits.map(&:sha256), query_sha256: Digest::SHA256.hexdigest(sentence),
    elapsed_seconds: elapsed.round(3), pass: pass
  }
end
after = {articles: KnowledgeArticle.count, versions: KnowledgeArticleVersion.count,
         approved: KnowledgeArticleVersion.where(status: 'approved').count,
         embeddings: KnowledgeChunkEmbedding.count}
report = {
  status: results.all? { |r| r[:pass] } && before == after ? 'PASS' : 'FAIL',
  captured_utc: Time.now.utc.iso8601,
  embedding_model: ModalEmbeddingClient::MODEL_ID,
  embedding_revision: ModalEmbeddingClient::MODEL_REVISION,
  reranker_model: ModalRerankerClient::MODEL_ID,
  reranker_revision: ModalRerankerClient::MODEL_REVISION,
  policy_sha256: Digest::SHA256.file(Rails.root.join(KnowledgeRelevanceGate::POLICY_FILE)).hexdigest,
  gpu_calls: results.size, parallel_instances: 1, seed: 'deterministic evaluation fixtures (no sampling)',
  before: before, after: after, cases: results
}
puts JSON.pretty_generate(report)
raise 'live relevance gate acceptance failed' unless report[:status] == 'PASS'
