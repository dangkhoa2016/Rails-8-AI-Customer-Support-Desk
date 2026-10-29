# frozen_string_literal: true
# Explicitly opt-in: M2_GPU_RUN=YES bin/rails runner script/m2_dual_4b_pilot.rb
# Without opt-in this is a read-only dry-run; no GPU, API request or DB vector write.
require 'json'
require 'digest'
require 'benchmark'
require 'fileutils'

raise 'synthetic development only' unless Rails.env.development? && ENV['M1_SYNTHETIC_DEMO'] == 'YES'
fixture_path = Rails.root.join('review/m2_dual_qwen3_4b_pilot_queries.json')
fixtures = JSON.parse(File.read(fixture_path))
proposals = Rails.root.join('review/m2_priority_editorial_proposals_20261029.json')
raise 'benchmark source drift' unless fixtures.fetch('source_sha256') == Digest::SHA256.file(proposals).hexdigest
cases = fixtures.fetch('cases')
raise 'expected 12 curated questions' unless cases.length == 12 &&
  cases.map { |c| [c.fetch('expected_article_key'), c.fetch('locale')] }.uniq.size == 12
org_slugs = cases.map { |c| c.fetch('tenant') }.uniq
raise 'unexpected tenant' unless org_slugs.sort == %w[novamart-store teamflow-cloud]
orgs = org_slugs.to_h { |slug| [slug, Organization.find_by!(slug: slug)] }
expected = KnowledgeArticleVersion.where(version_number: 2, status: 'approved').count
raise 'expected exactly 12 approved editorial versions' unless expected == 12

state = orgs.transform_values do |org|
  { approved_chunks: KnowledgeEmbeddingIngestion.eligible_chunks(organization: org).count,
    stored_vectors: KnowledgeChunkEmbedding.where(organization_id: org.id,
      model_id: ModalEmbeddingClient::MODEL_ID, model_revision: ModalEmbeddingClient::MODEL_REVISION).count }
end
unless ENV['M2_GPU_RUN'] == 'YES'
  puts JSON.pretty_generate(mode: 'DRY_RUN', models: [ModalEmbeddingClient::MODEL_ID, ModalRerankerClient::MODEL_ID],
    embedding_dimensions: 2560, tenants: state, test_cases: cases.length, outbound_requests: 0,
    note: 'No Modal credentials used, no GPU calls or database writes.')
  exit(0)
end

embedder = ModalEmbeddingClient.new
reranker = ModalRerankerClient.new
ingestion = []
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
orgs.each do |slug, org|
  rounds = 0
  loop do
    raise 'ingestion round limit exceeded' if rounds >= 24
    result = KnowledgeEmbeddingIngestion.ingest!(organization: org, client: embedder, max_chunks: 8)
    ingestion << { tenant: slug, embedded: result.fetch(:embedded), eligible_remaining: result.fetch(:eligible_remaining) }
    break if result.fetch(:embedded) == 0
    rounds += 1
  end
end

entries = cases.map do |c|
  org = orgs.fetch(c.fetch('tenant'))
  query = c.fetch('query')
  expected_key = c.fetch('expected_article_key')
  elapsed_ms = nil
  reranked = nil
  elapsed_ms = Benchmark.realtime do
    reranked = KnowledgeRerankedRetrieval.search(
      organization: org, role: 'agent', query: query, locale: c.fetch('locale'),
      embedding_client: embedder, reranker_client: reranker, limit: 5,
      candidate_limit: 12, query_privacy_reviewed: true)
  end * 1000
  { case_id: c.fetch('case_id'), tenant: org.slug, locale: c.fetch('locale'),
    expected_article: expected_key, top1: reranked.first&.article_key,
    top5: reranked.map(&:article_key), hit_at_5: reranked.any? { |h| h.article_key == expected_key },
    reciprocal_rank: (i = reranked.index { |h| h.article_key == expected_key }) ? 1.0 / (i + 1) : 0.0,
    elapsed_ms: elapsed_ms.round(1), citations: reranked.map(&:citation),
    query_sha256: Digest::SHA256.hexdigest(query) }
end
summary = { status: 'LIVE_MODELS_EXECUTED', captured_utc: Time.now.utc.iso8601,
  models: [{ id: embedder.model_id, revision: embedder.model_revision, dimension: 2560 },
           { id: reranker.model_id, revision: reranker.model_revision, score_type: 'raw_logit' }],
  cases: entries.size, hit_at_5_rate: entries.count { |e| e[:hit_at_5] }.to_f / entries.size,
  mrr_at_5: entries.sum { |e| e[:reciprocal_rank] } / entries.size,
  full_wall_seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(2),
  ingestion: ingestion, queries: entries }
outdir = Rails.root.join('evidence-m2-dual-qwen3-4b-live')
FileUtils.mkdir_p(outdir)
File.write(outdir.join('pilot-results.json'), JSON.pretty_generate(summary) + "\n")
puts JSON.pretty_generate(summary.except(:queries))
