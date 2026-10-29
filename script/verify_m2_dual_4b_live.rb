# frozen_string_literal: true
# Live-data acceptance gates for synthetic M2 4B/4B deployment.
# Database reads only. No Modal HTTP request or business write.
require 'json'
require 'digest'
require 'set'
require 'time'

raise 'synthetic development only' unless Rails.env.development? && ENV['M1_SYNTHETIC_DEMO'] == 'YES'
model = ModalEmbeddingClient::MODEL_ID
revision = ModalEmbeddingClient::MODEL_REVISION
proposal_file = Rails.root.join('review/m2_priority_editorial_proposals_20261029.json')
proposals = JSON.parse(File.read(proposal_file)).fetch('revisions')
pilot_file = Rails.root.join('evidence-m2-dual-qwen3-4b-live/pilot-results.json')
pilot = JSON.parse(File.read(pilot_file))
raise 'not a completed live pilot' unless pilot.fetch('status') == 'LIVE_MODELS_EXECUTED' &&
  pilot.fetch('cases') == 12 && pilot.fetch('queries').size == 12
expected = {'teamflow-cloud' => 28, 'novamart-store' => 56}
errors = []
checks = []
fake_client = Struct.new(:model_id, :model_revision) do
  def embed_documents(*)
    raise 'unexpected Modal GPU call: DB should already contain all vectors'
  end
end.new(model, revision)

expected.each do |tenant, count|
  org = Organization.find_by!(slug: tenant)
  scope = KnowledgeEmbeddingIngestion.eligible_chunks(organization: org)
  embedded = KnowledgeChunkEmbedding.where(organization_id: org.id, model_id: model, model_revision: revision)
  errors << "eligible count wrong #{tenant}" unless scope.count == count
  errors << "vector count wrong #{tenant}" unless embedded.count == count
  embedded.includes(knowledge_chunk: :knowledge_article_version).find_each do |row|
    chunk = row.knowledge_chunk
    version = chunk.knowledge_article_version
    errors << "cross-tenant embedding id #{row.id}" unless row.organization_id == chunk.organization_id &&
      version.organization_id == org.id
    errors << "draft/stale embedding id #{row.id}" unless version.active_on?(Date.current) &&
      version.policy_version == org.policy_version &&
      version.status == 'approved' && version.version_number == 2
    errors << "SHA drift #{row.id}" unless row.content_sha256 == chunk.sha256 &&
      Digest::SHA256.hexdigest(chunk.body) == chunk.sha256
  end
  status = KnowledgeEmbeddingIngestion.ingest!(organization: org, client: fake_client, max_chunks: 8)
  errors << "not idempotent #{tenant}" unless status[:embedded] == 0 && status[:eligible_remaining] == 0
  sample = [1.0] + Array.new(2559, 0.0)
  %w[vi en].each do |lang|
    %w[viewer agent].each do |role|
      hits = KnowledgeSemanticRetrieval.search(organization: org, role: role, embedding: sample,
        locale: lang, model_id: model, model_revision: revision, limit: 8)
      hits.each do |hit|
        article = KnowledgeArticle.find_by!(organization_id: org.id, article_key: hit.article_key)
        version = KnowledgeArticleVersion.find(hit.article_version_id)
        errors << "unauthorized tenant/revision in result #{hit.citation}" unless
          article.organization_id == org.id && version.organization_id == org.id &&
          version.status == 'approved' && version.locale == lang && version.version_number == 2 &&
          hit.citation.include?("@#{lang}:v2#chunk-") &&
          Digest::SHA256.hexdigest(hit.content) == hit.sha256 &&
          (role == 'agent' || article.audience == 'public')
      end
      checks << {tenant: tenant, role: role, locale: lang, filtered_hits: hits.size,
                 citations: hits.map(&:citation)}
    end
  end
end

proposals.each do |row|
  org = Organization.find_by!(slug: row.fetch('organization_slug'))
  article = KnowledgeArticle.find_by!(organization: org, article_key: row.fetch('article_key'))
  ver = KnowledgeArticleVersion.find_by!(organization: org, knowledge_article: article,
    version_number: 2, locale: row.fetch('locale'))
  errors << "approved proposal drift #{article.article_key}/#{ver.locale}" unless
    ver.sha256 == row.fetch('sha256') && ver.status == 'approved' && ver.approved_by.present?
end
errors << 'unexpected v1 approval' unless KnowledgeArticleVersion.where(version_number: 1, status: 'draft').count == 200
errors << 'unexpected approved version count' unless KnowledgeArticleVersion.where(status: 'approved').count == 12
errors << 'unexpected embeddings' unless KnowledgeChunkEmbedding.count == 84
errors << 'case answers mismatch' unless pilot.fetch('queries').all? do |query|
  query.fetch('top1') == query.fetch('expected_article') && query.fetch('hit_at_5')
end
summary = {
  status: errors.empty? ? 'PASS_LIVE_EMBEDDED_DB_AND_FILTERED_RETRIEVAL' : 'FAIL',
  captured_utc: Time.now.utc.iso8601,
  model: model, revision: revision, dimensions: 2560,
  organization_counts: expected,
  approved_versions: KnowledgeArticleVersion.where(status: 'approved').count,
  v1_drafts: KnowledgeArticleVersion.where(version_number: 1, status: 'draft').count,
  embeddings: KnowledgeChunkEmbedding.count,
  idempotency: 'PASS_NO_GPU_CALLS' ,
  tenant_acl_locale_checks: checks,
  live_benchmark_queries: pilot.fetch('cases'),
  recall_at_5: pilot.fetch('hit_at_5_rate'),
  mrr_at_5: pilot.fetch('mrr_at_5'),
  errors: errors
}
puts JSON.pretty_generate(summary)
raise 'M2 live acceptance failed' unless errors.empty?
