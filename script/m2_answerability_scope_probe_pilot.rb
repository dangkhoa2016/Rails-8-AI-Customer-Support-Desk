# frozen_string_literal: true
# Diagnostic only. Compare Reranker-4B matches against independently authored
# question-intent probes, using only the already scored synthetic evaluation set.
require 'json'
require 'digest'
require 'time'
require 'benchmark'
require 'fileutils'

raise 'development synthetic mode only' unless Rails.env.development? && ENV['M1_SYNTHETIC_DEMO'] == 'YES'
raise 'explicit bounded GPU pilot required' unless ENV['M2_SCOPE_PROBE_GPU'] == 'YES'
root = Rails.root
base = root.join('evidence-m2-answerability-20261029')
FileUtils.mkdir_p(base)
output = base.join('scope-probe-pilot.jsonl')
raise 'refuse to overwrite existing pilot output' if output.exist?
scope_file = root.join('review/m2_answerability_scope_probes_20261029.json')
matrix = JSON.parse(scope_file.read).fetch('items').index_by { |v| [v.fetch('article_key'), v.fetch('locale')] }
raise 'unexpected probe matrix' unless matrix.size == 12
rankings = %w[live-eval.jsonl stress-eval.jsonl lockbox-eval.jsonl final-holdout.jsonl].flat_map do |name|
  File.readlines(root.join('evidence-m2-relevance-20261029', name)).map { |row| JSON.parse(row) }
end
prompts = %w[m2_relevance_eval_20261029.json m2_relevance_stress_eval_20261029.json m2_relevance_lockbox_eval_20261029.json m2_relevance_final_holdout_20261029.json].flat_map do |name|
  JSON.parse(root.join('review',name).read).fetch('cases')
end.index_by {|r| r.fetch('id')}
raise 'incomplete input' unless rankings.size == 72 && prompts.size == 72
# Focus on near-domain questions that can trick a relevance gate; include all supported examples.
# Preserve ascending input order; threshold here selects diagnostic cases, NOT a production cutoff.
selected = rankings.select do |r|
  r['expected_article_key'] || r.fetch('result').first.fetch('score_logit') >= 0
end
max_cases = Integer(ENV.fetch('M2_SCOPE_PROBE_MAX', '36'))
raise 'pilot cost budget 1..72' unless max_cases.between?(1,72)
selected = selected.first(max_cases)
client = ModalRerankerClient.new
puts "SCOPE_DIAGNOSTIC_BEGIN cases=#{selected.size} probe_sha256=#{Digest::SHA256.file(scope_file).hexdigest}"
STDOUT.sync = true
File.open(output,'w',0o600) do |io|
  selected.each_with_index do |r,i|
    input = prompts.fetch(r.fetch('id'))
    query = input.fetch('query')
    raise 'query checksum mismatch' unless Digest::SHA256.hexdigest(query) == r.fetch('query_sha256')
    top1 = r.fetch('result').first
    c = matrix.fetch([top1.fetch('article_key'),r.fetch('locale')])
    supported = c.fetch('supported')
    unsupported = c.fetch('unsupported')
    raise 'too many probes' unless supported.size == 4 && unsupported.size == 4
    scored = nil
    elapsed = Benchmark.realtime { scored = client.score(query:query, documents: supported + unsupported) }
    pmax = scored.first(4).max
    nmax = scored.drop(4).max
    out = {
      id: r.fetch('id'), tenant: r.fetch('tenant'), locale: r.fetch('locale'),
      article_key:top1.fetch('article_key'), label: r.fetch('expected_article_key').nil? ? 'unsupported' : 'supported',
      gold_article: r.fetch('expected_article_key'), query_sha256:r.fetch('query_sha256'),
      initial_top1_logit: top1.fetch('score_logit'),
      supported_probe_max:pmax, unsupported_probe_max:nmax,
      delta:pmax-nmax, scores_supported:scored.first(4), scores_unsupported:scored.drop(4),
      elapsed_s:elapsed.round(3)
    }
    io.puts(JSON.generate(out));io.flush
    puts "probe=#{i+1}/#{selected.size} id=#{out[:id]} label=#{out[:label]} p=#{pmax.round(3)} n=#{nmax.round(3)} delta=#{(pmax-nmax).round(3)}"
  end
end
puts "SCOPE_DIAGNOSTIC_DONE sha256=#{Digest::SHA256.file(output).hexdigest}"
