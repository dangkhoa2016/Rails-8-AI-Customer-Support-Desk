# frozen_string_literal: true
require 'json'
require 'digest'

# M2 synthetic demo activation interlock. Does NOT verify reasoning entailment.
# Current sealed evaluation FAILED; enabling an experimental flag must never
# silently bypass the failed evidence. An eligible result requires an explicit
# future, independently frozen acceptance run and a code-level review.
class KnowledgeScopePreviewGate
  MANIFEST = 'review/m2_scope_sealed_challenge80_20261029.json'
  EVIDENCE = 'data/security/sealed80-acceptance.json'
  RESULTS = 'data/security/sealed80-live-results.jsonl'

  def self.eligible?
    report = JSON.parse(File.binread(Rails.root.join(EVIDENCE)))
    manifest_bytes = File.binread(Rails.root.join(MANIFEST))
    manifest = JSON.parse(manifest_bytes)
    output_bytes = File.binread(Rails.root.join(RESULTS))
    cases = manifest.fetch('cases')
    scores = output_bytes.lines.map { |line| JSON.parse(line) }

    return false unless report.fetch('status') == 'COMPLETED' &&
      report.fetch('decision') == 'ELIGIBLE_FOR_ISOLATED_PREVIEW_SMOKE' &&
      report.fetch('sealed_manifest_sha256') == Digest::SHA256.hexdigest(manifest_bytes) &&
      report.fetch('results_sha256') == Digest::SHA256.hexdigest(output_bytes) &&
      report.fetch('policy_sha256') ==
        Digest::SHA256.file(Rails.root.join(KnowledgeAnswerabilityScopeVerifier::POLICY_FILE)).hexdigest &&
      cases.size == 80 && scores.size == 80 &&
      scores.map { |r| r.fetch('id') } == cases.map { |c| c.fetch('id') } &&
      report.fetch('adjudication_rule') == manifest.fetch('lockbox_rules') &&
      manifest.fetch('lockbox_rules').fetch('max_false_positive_for_preview_enable') == 0 &&
      manifest.fetch('lockbox_rules').fetch('min_supported_recall_for_preview_enable') >= 0.8

    metrics = report.fetch('combined')
    supported = scores.count { |row| row['gold_article'] }
    true_positive = scores.count { |row| row['gold_article'] && row['combined_correct'] }
    false_positive = scores.count { |row| row['combined_accepted'] && !row['gold_article'] }
    raise IOError, 'invalid expected positive count' unless supported == 20

    return false unless false_positive == 0 && metrics.fetch('fp') == 0 &&
      true_positive >= 16 && metrics.fetch('tp') == true_positive &&
      report.fetch('supported_recall') >= 0.8 &&
      report.fetch('db_before') == report.fetch('db_after')

    pins = report.fetch('model_pins')
    return false unless pins.fetch('embedding') == ModalEmbeddingClient::MODEL_ID &&
      pins.fetch('embedding_revision') == ModalEmbeddingClient::MODEL_REVISION &&
      pins.fetch('reranker') == ModalRerankerClient::MODEL_ID &&
      pins.fetch('reranker_revision') == ModalRerankerClient::MODEL_REVISION

    KnowledgeRelevanceGate.pilot.validate!
    %w[teamflow-cloud novamart-store].each do |slug|
      KnowledgeAnswerabilityScopeVerifier.pilot.validate!(
        organization: Organization.find_by!(slug: slug), locale: 'en'
      )
    end
    true
  rescue Errno::ENOENT, JSON::ParserError, KeyError, ArgumentError,
    IOError, ActiveRecord::RecordNotFound, TypeError
    false
  end
end
