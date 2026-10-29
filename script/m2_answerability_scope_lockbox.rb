# frozen_string_literal: true
# Frozen diagnostic second-stage scope contrast on the multi-intent lockbox.
# Threshold fixed from a separate 36-case discovery pilot; never re-fit here.
require 'json'
require 'digest'
require 'benchmark'
require 'fileutils'
require 'time'
raise 'synthetic development only' unless Rails.env.development? && ENV['M1_SYNTHETIC_DEMO'] == 'YES'
raise 'explicit scoped GPU budget flag required' unless ENV['M2_SCOPE_LOCKBOX_GPU'] == 'YES'

root=Rails.root
base=root.join('evidence-m2-answerability-20261029')
output=base.join('multi-intent-scope-probe.jsonl')
raise 'refuse to overwrite' if output.exist?
fixture=root.join('review/m2_answerability_multi_intent_lockbox_20261029.json')
source=base.join('multi-intent-retrieval-v2.jsonl')
contracts=root.join('review/m2_answerability_scope_probes_20261029.json')
rows=File.readlines(source).map {|line| JSON.parse(line)}
prompts=JSON.parse(fixture.read).fetch('cases').index_by {|r| r.fetch('id')}
matrix=JSON.parse(contracts.read).fetch('items').index_by {|r| [r.fetch('article_key'),r.fetch('locale')]}
raise 'unexpected run size' unless rows.size == 24 && prompts.size==24 && matrix.size==12
budget=Integer(ENV.fetch('M2_SCOPE_LOCKBOX_MAX','24'))
raise 'budget must be exactly 24 for frozen lockbox' unless budget==24
THRESHOLD=5.05078125
BASELINE_CUTOFF=7.421875
client=ModalRerankerClient.new
STDOUT.sync=true
puts "LOCKBOX_SCOPE_START cutoff=#{THRESHOLD} original_sha=#{Digest::SHA256.file(source).hexdigest}"
File.open(output,'w',0o600) do |io|
  rows.each_with_index do |row,i|
    inp=prompts.fetch(row.fetch('id'))
    query=inp.fetch('query')
    raise 'query hash mismatch' unless Digest::SHA256.hexdigest(query)==row.fetch('query_sha256')
    hit=row.fetch('result').first
    contract=matrix.fetch([hit.fetch('article_key'),row.fetch('locale')])
    sup=contract.fetch('supported')
    neg=contract.fetch('unsupported')
    raise 'invalid contract' unless sup.length==4 && neg.length==4
    scores=nil
    elapsed=Benchmark.realtime { scores=client.score(query:query,documents:sup+neg) }
    delta=scores.first(4).max-scores.drop(4).max
    baseline=hit.fetch('score_logit').to_f >= BASELINE_CUTOFF
    new_accepted=baseline && delta >= THRESHOLD
    gold=!row.fetch('expected_article_key').nil?
    record={
      id:row.fetch('id'), tenant:row.fetch('tenant'),locale:row.fetch('locale'),
      query_sha256:row.fetch('query_sha256'), gold_support:gold,
      target_article:hit.fetch('article_key'), gold_article:row.fetch('expected_article_key'),
      retrieval_score:hit.fetch('score_logit'),
      supported_probe_max:scores.first(4).max,
      unsupported_probe_max:scores.drop(4).max,
      scope_margin:delta, frozen_scope_margin_cutoff:THRESHOLD,
      baseline_accepted:baseline, combined_accepted:new_accepted,
      elapsed_seconds:elapsed.round(3)
    }
    io.puts(JSON.generate(record));io.flush
    puts "scope=#{i+1}/24 #{row.fetch('id')} gold=#{gold} margin=#{delta.round(3)} combined=#{new_accepted}"
  end
end
puts "LOCKBOX_SCOPE_COMPLETE sha256=#{Digest::SHA256.file(output).hexdigest}"
