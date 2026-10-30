# frozen_string_literal: true
# Bounded, privacy-reviewed, read-only M5 live inference pilot.
require 'json'
require 'digest'
require 'benchmark'
require 'time'
require 'fileutils'

raise 'requires synthetic development environment' unless Rails.env.development? && ENV['M1_SYNTHETIC_DEMO'] == 'YES'
raise 'explicit M5 live pilot opt-in required' unless ENV['M5_LIVE_SYNTHETIC_PILOT'] == 'YES'
raise 'scope lockbox must remain blocked' if KnowledgeScopePreviewGate.eligible?
raise 'semantic UI should remain disabled during bounded pilot' unless ENV['M2_SEMANTIC_UI_ENABLE'] == 'NO'
raise 'answerability scope must remain disabled' unless ENV['M2_ANSWERABILITY_SCOPE_ENABLE'] == 'NO'
gate = KnowledgeRelevanceGate.pilot
gate.validate!
root = Rails.root
source = root.join('review/m2_dual_qwen3_4b_pilot_queries.json')
dataset = JSON.parse(File.read(source))
selected_ids = %w[M2-4B-01 M2-4B-02 M2-4B-07 M2-4B-08]
selected = selected_ids.map {|id| dataset.fetch('cases').find {|x| x.fetch('case_id') == id} || (raise "missing case #{id}") }
raise 'wrong tenant/locale coverage' unless selected.map {|x| [x['tenant'],x['locale']]}.uniq.size == 4
raise 'unexpected source' unless selected.all? {|x| x['query'].is_a?(String) && x['query'].length.between?(12,300)}
expected = {'teamflow-cloud' => 'TF-', 'novamart-store' => 'NM-'}
outdir = root.join('evidence-m5-live-recovery-20261030')
FileUtils.mkdir_p(outdir)
output = outdir.join('m5-pilot-four-readonly.jsonl')
raise 'refuse to overwrite pilot evidence' if File.exist?(output)
embedding = ModalEmbeddingClient.new
reranker = ModalRerankerClient.new
base = {
  kind: 'M5_LIVE_PILOT_SYNTHETIC_NON_GOLD',
  input_dataset_sha256: Digest::SHA256.file(source).hexdigest,
  pinned_embedding_model: embedding.model_id,
  embedding_revision: embedding.model_revision,
  pinned_reranker_model: reranker.model_id,
  reranker_revision: reranker.model_revision,
  semantic_gold: false,
  sealed80: 'BLOCKED',
  writes: 'NONE',
  gpu_instances_requested_per_model: 1
}
$stdout.sync = true
puts JSON.generate({event:'begin',case_ids:selected_ids,model_pair:'QWEN3_4B_4B',sealed80:'BLOCKED'})
File.open(output, File::WRONLY | File::CREAT | File::EXCL, 0600) do |io|
  selected.each_with_index do |c,i|
    org = Organization.find_by!(slug:c.fetch('tenant'))
    query = c.fetch('query')
    record = base.merge(case_id:c.fetch('case_id'), tenant:org.slug, locale:c.fetch('locale'),
      source_expected_article_hint:c.fetch('expected_article_key'),
      query_sha256:Digest::SHA256.hexdigest(query), started_utc:Time.now.utc.iso8601)
    begin
      hits = nil
      ms = Benchmark.realtime do
        hits = KnowledgeRerankedRetrieval.search(
          organization:org,role:'agent',query:query,locale:c.fetch('locale'),
          embedding_client:embedding,reranker_client:reranker,
          candidate_limit:12,limit:5,query_privacy_reviewed:true,
          relevance_gate:gate,answerability_verifier:nil
        )
      end*1000
      raise 'unexpected cross tenant citation' unless hits.all? {|h| h.article_key.start_with?(expected.fetch(org.slug))}
      raise 'unexpected locale citation' unless hits.all? {|h| h.locale == c.fetch('locale')}
      record[:status] = 'PASS_LIVE_AUTHENTICATED_READONLY'
      record[:elapsed_ms] = ms.round(1)
      record[:returned_count] = hits.length
      record[:top1_matches_source_hint] = hits.first&.article_key == c.fetch('expected_article_key')
      record[:citations] = hits.map do |hit|
        { article_key:hit.article_key, version_id:hit.article_version_id,
          locale:hit.locale, citation:hit.citation, chunk_sha256:hit.sha256,
          cosine_distance:hit.cosine_distance&.round(6), rerank_logit:hit.rerank_score&.round(5) }
      end
    rescue StandardError => e
      record[:status] = 'ERROR'
      record[:error_class] = e.class.name
      # Do not log exception messages: remote errors may contain endpoints/credentials.
      io.puts JSON.generate(record)
      io.flush
      puts JSON.generate({event:'case_error',case_id:c.fetch('case_id'),error_class:e.class.name})
      raise
    end
    record[:finished_utc] = Time.now.utc.iso8601
    io.puts JSON.generate(record)
    io.flush
    puts JSON.generate({event:'case_pass',case_id:record[:case_id],elapsed_ms:record[:elapsed_ms],
      top1:record[:citations].first&.fetch(:article_key,nil),count:record[:returned_count],progress:"#{i+1}/#{selected.length}"})
  end
end
puts JSON.generate({event:'complete',cases:selected.length,
  evidence_sha256:Digest::SHA256.file(output).hexdigest,answerability:'BLOCKED'})
