# frozen_string_literal: true
# Actual READ-ONLY PostgreSQL lexical baseline; no Modal model inference.
require 'json'
require 'digest'
require 'benchmark'
require 'fileutils'
raise 'synthetic development only' unless Rails.env.development? && ENV['M1_SYNTHETIC_DEMO'] == 'YES'
file = Rails.root.join('review/m2_dual_qwen3_4b_pilot_queries.json')
fixture = JSON.parse(File.read(file))
cases = fixture.fetch('cases')
results = cases.map do |item|
  org = Organization.find_by!(slug: item.fetch('tenant'))
  hits = nil
  ms = Benchmark.realtime do
    hits = KnowledgeRetrieval.search(organization: org, role: 'agent',
      query: item.fetch('query'), locale: item.fetch('locale'), limit: 8)
  end * 1000
  rank = hits.index { |h| h.article_key == item.fetch('expected_article_key') }
  { case_id: item.fetch('case_id'), expected_article: item.fetch('expected_article_key'),
    tenant: item.fetch('tenant'), locale: item.fetch('locale'),
    retrieved_articles: hits.map(&:article_key), hit_at_8: !!rank,
    reciprocal_rank: rank ? 1.0 / (rank + 1) : 0.0,
    latency_ms: ms.round(2) }
end
summary = { status: 'POSTGRES_LEXICAL_ACTUAL_RESULTS', count: results.size,
  recall_at_8: results.count { |r| r[:hit_at_8] }.to_f / results.size,
  mrr_at_8: results.sum { |r| r[:reciprocal_rank] } / results.size,
  source_sha256: Digest::SHA256.file(file).hexdigest, results: results,
  caveat: 'Only 12 pilot queries and six approved articles; not a statistically representative evaluation' }
out = Rails.root.join('evidence-m2-dual-qwen3-4b-preflight')
FileUtils.mkdir_p(out)
File.write(out.join('lexical-baseline.json'), JSON.pretty_generate(summary) + "\n")
puts JSON.pretty_generate(summary)
