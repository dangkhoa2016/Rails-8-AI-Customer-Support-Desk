# frozen_string_literal: true
# Deterministic, read-only calibration from independently labeled live GPU evidence.
# An original calibration/holdout/stress/lockbox history is retained verbatim.
require 'json'
require 'digest'
require 'time'

raise 'synthetic development only' unless Rails.env.development? && ENV['M1_SYNTHETIC_DEMO'] == 'YES'
root = Rails.root
inputs = %w[live-eval.jsonl stress-eval.jsonl lockbox-eval.jsonl]
base = root.join('evidence-m2-relevance-20261029')
records = inputs.flat_map do |name|
  File.readlines(base.join(name)).map { |line| JSON.parse(line) }
end
fresh = File.readlines(base.join('final-holdout.jsonl')).map { |line| JSON.parse(line) }
raise 'missing calibration records' unless records.size == 60 && fresh.size == 12

score = ->(r) { r.fetch('result').first.fetch('score_logit').to_f }
positive = ->(r) { !r['expected_article_key'].nil? }
pos = records.select(&positive)
neg = records.reject(&positive)
highest_negative = neg.map(&score).max
lowest_positive_above = pos.map(&score).select { |s| s > highest_negative }.min
raise 'no safe pilot cutoff available' if lowest_positive_above.nil?
threshold = (highest_negative + lowest_positive_above) / 2.0

metrics = lambda do |set|
  supported = set.select(&positive)
  unsupported = set.reject(&positive)
  {
    supported: supported.size,
    accepted_supported_with_correct_top1: supported.count { |r| score.call(r) >= threshold && r.fetch('top1_matches_gold') == true },
    rejected_supported: supported.count { |r| score.call(r) < threshold },
    unsupported: unsupported.size,
    accepted_unsupported_false_positive: unsupported.count { |r| score.call(r) >= threshold },
    rejected_unsupported: unsupported.count { |r| score.call(r) < threshold }
  }
end

final_metrics = metrics.call(fresh)
raise 'final holdout false positive, not eligible for UI gate' unless final_metrics.fetch(:accepted_unsupported_false_positive).zero?
raise 'final holdout lost all supported queries' if final_metrics.fetch(:accepted_supported_with_correct_top1).zero?
fingerprint_rows = KnowledgeArticleVersion.where(status: 'approved').order(:id).pluck(:id, :sha256)
raise 'approved baseline changed' unless fingerprint_rows.size == 12 && KnowledgeChunkEmbedding.count == 84
organization_policy_versions = Organization.where(slug: %w[teamflow-cloud novamart-store]).order(:slug).pluck(:slug, :policy_version).to_h
source_hashes = (inputs + ['final-holdout.jsonl']).to_h { |name| [name, Digest::SHA256.file(base.join(name)).hexdigest] }
manifest_names = %w[m2_relevance_eval_20261029.json m2_relevance_stress_eval_20261029.json m2_relevance_lockbox_eval_20261029.json m2_relevance_final_holdout_20261029.json]
manifest_hashes = manifest_names.to_h { |name| [name, Digest::SHA256.file(root.join('review', name)).hexdigest] }

config = {
  id: 'M2_RELEVANCE_PILOT_CONSERVATIVE_V1',
  status: 'EXPERIMENTAL_PILOT_NOT_PRODUCTION',
  algorithm: 'accept_chunk_if_raw_rerank_logit_at_least_threshold',
  calibrated_from: '60 labeled synthetic queries, cutoff above maximum negative logit',
  threshold_logit: threshold,
  calibration_max_negative_logit: highest_negative,
  calibration_next_positive_logit: lowest_positive_above,
  selection_rule: 'midpoint between highest negative and next positive, prioritizing zero observed false positives',
  calibration: metrics.call(records),
  untouched_final_holdout: final_metrics,
  qa_note: 'Some supported questions can be withheld. Raw logits are not probabilities. Test sample is too small to guarantee generalization.',
  embedding_model: ModalEmbeddingClient::MODEL_ID,
  embedding_revision: ModalEmbeddingClient::MODEL_REVISION,
  reranker_model: ModalRerankerClient::MODEL_ID,
  reranker_revision: ModalRerankerClient::MODEL_REVISION,
  approved_version_count: 12,
  approved_versions_sha256: Digest::SHA256.hexdigest(fingerprint_rows.to_json),
  embedding_count: 84,
  organization_policy_versions: organization_policy_versions,
  source_result_sha256: source_hashes,
  manifest_sha256: manifest_hashes,
  created_utc: Time.now.utc.iso8601
}
file = root.join('review/m2_relevance_gate_pilot_20261029.json')
raise 'refusing overwrite of calibrated gate' if File.exist?(file)
File.write(file, JSON.pretty_generate(config) + "\n")
puts JSON.pretty_generate(config)
