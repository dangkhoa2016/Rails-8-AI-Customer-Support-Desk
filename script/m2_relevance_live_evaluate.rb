# frozen_string_literal: true
# Run with: M2_EVAL_MAX_CASES=32 bin/rails runner script/m2_relevance_live_evaluate.rb
# Curated synthetic questions only; strictly read-only DB + outbound 4B/4B GPU.
require 'json'
require 'digest'
require 'benchmark'
require 'time'
require 'fileutils'

raise 'development-only synthetic pilot required' unless Rails.env.development? && ENV['M1_SYNTHETIC_DEMO'] == 'YES'
manifest_path = Rails.root.join(ENV.fetch('M2_EVAL_MANIFEST', 'review/m2_relevance_eval_20261029.json'))
manifest_bytes = File.binread(manifest_path)
cases = JSON.parse(manifest_bytes).fetch('cases')
raise 'invalid evaluation manifest' unless cases.size.between?(1, 32) && cases.map { |c| c.fetch('id') }.uniq.size == cases.size
limit = Integer(ENV.fetch('M2_EVAL_MAX_CASES', cases.size.to_s))
raise 'GPU budget limit 1..32' unless limit.between?(1, 32) && limit <= cases.size
raise 'explicit GPU pilot authorization needed' unless ENV['M2_EVAL_LIVE_GPU'] == 'YES'
raise 'unexpected approved KB version count' unless KnowledgeArticleVersion.where(status: 'approved').count == 12
raise 'unexpected embedding count' unless KnowledgeChunkEmbedding.count == 84

out = Rails.root.join(ENV.fetch('M2_EVAL_OUT', 'evidence-m2-relevance-20261029/live-eval.jsonl'))
FileUtils.mkdir_p(out.dirname)
raise 'refusing to overwrite existing GPU evidence' if File.exist?(out)
STDOUT.sync = true
embed = ModalEmbeddingClient.new
rerank = ModalRerankerClient.new
puts "LIVE_RELEVANCE_EVAL_START cases=#{limit} manifest_sha256=#{Digest::SHA256.hexdigest(manifest_bytes)}"
File.open(out, 'w', 0o600) do |file|
  cases.first(limit).each_with_index do |item, index|
    org = Organization.find_by!(slug: item.fetch('tenant'))
    query = item.fetch('query')
    raise 'invalid synthetic query size' unless query.length.between?(12, 300)
    elapsed = Benchmark.realtime do
      hits = KnowledgeRerankedRetrieval.search(organization: org, role: 'agent',
        query: query, locale: item.fetch('locale'),
        embedding_client: embed, reranker_client: rerank,
        candidate_limit: 12, limit: 5, query_privacy_reviewed: true)
      hit_data = hits.map do |hit|
        {
          article_key: hit.article_key,
          citation: hit.citation,
          score_logit: hit.rerank_score,
          cosine_distance: hit.cosine_distance,
          sha256: hit.sha256
        }
      end
      record = item.except('query').merge(query_sha256: Digest::SHA256.hexdigest(query),
        result: hit_data, top1_matches_gold: item['expected_article_key'] && (hits.first&.article_key == item['expected_article_key']))
      file.puts(JSON.generate(record))
      file.flush
    end
    puts "case=#{index+1}/#{limit} id=#{item.fetch('id')} tenant=#{item.fetch('tenant')} split=#{item.fetch('split', 'unspecified')} elapsed_sec=#{elapsed.round(2)}"
  end
end
puts "LIVE_RELEVANCE_EVAL_COMPLETE output=#{out} sha256=#{Digest::SHA256.file(out).hexdigest}"
