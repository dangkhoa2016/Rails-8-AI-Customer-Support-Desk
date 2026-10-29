# frozen_string_literal: true
require 'json'
require 'digest'
require 'benchmark'
require 'fileutils'
raise 'synthetic environment only' unless Rails.env.development? && ENV['M1_SYNTHETIC_DEMO'] == 'YES'
raise 'explicit smoke opt-in required' unless ENV['M2_4B_SMOKE'] == 'YES'
section = ENV.fetch('M2_4B_SMOKE_STAGE', 'embedding')
outdir = Rails.root.join('evidence-m2-dual-qwen3-4b-runtime')
FileUtils.mkdir_p(outdir)
if section == 'embedding'
  client = ModalEmbeddingClient.new
  text = 'What happens if an invoice is paid but my workspace plan has not activated?'
  response = nil
  ms = Benchmark.realtime { response = client.embed_query(text) } * 1000
  raise IOError, 'unexpected vector dimensions' unless response.length == 2560
  info = { status: 'PASS_REAL_EMBEDDING', model: client.model_id, revision: client.model_revision,
    dimensions: response.length, vector_norm: Math.sqrt(response.sum { |v| v.to_f ** 2 }).round(6),
    elapsed_ms: ms.round(1), query_sha256: Digest::SHA256.hexdigest(text), runtime: 'Modal GPU actual' }
  File.write(outdir.join('embedding-smoke.json'), JSON.pretty_generate(info) + "\n")
  puts JSON.pretty_generate(info)
elsif section == 'reranker'
  client = ModalRerankerClient.new
  query = 'An invoice is paid but the workspace plan was not activated.'
  docs = ['The invoice is paid but activation succeeded only after an event.',
          'NovaMart shipping rules are different from TeamFlow billing.']
  values = nil
  ms = Benchmark.realtime { values = client.score(query: query, documents: docs) } * 1000
  info = { status: 'PASS_REAL_RERANKER', model: client.model_id, revision: client.model_revision,
    scores: values, elapsed_ms: ms.round(1), query_sha256: Digest::SHA256.hexdigest(query),
    document_sha256: docs.map { |d| Digest::SHA256.hexdigest(d) }, runtime: 'Modal GPU actual' }
  File.write(outdir.join('reranker-smoke.json'), JSON.pretty_generate(info) + "\n")
  puts JSON.pretty_generate(info)
else
  raise 'unexpected smoke stage'
end
