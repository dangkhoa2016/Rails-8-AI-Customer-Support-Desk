# frozen_string_literal: true
require 'json'
require 'digest'
proposal_path = Rails.root.join('review/m2_priority_editorial_proposals_20261029.json')
data = JSON.parse(File.read(proposal_path))
issues = []
checks = data.fetch('revisions').map do |row|
  org = Organization.find_by!(slug: row.fetch('organization_slug'))
  article = KnowledgeArticle.find_by!(organization: org, article_key: row.fetch('article_key'))
  version = KnowledgeArticleVersion.find_by!(organization: org, knowledge_article: article,
    version_number: 2, locale: row.fetch('locale'))
  matching_audit = AuditEvent.where(organization_id: org.id, action: 'kb.version_approved').select do |event|
    event.metadata['article_key'] == article.article_key && event.metadata['locale'] == version.locale &&
      event.metadata['sha256'] == version.sha256 &&
      event.metadata['approval_origin'] == 'user_chat_confirmation_2026_10_29' &&
      event.metadata['audit_actor_kind'] == 'synthetic_demo_tenant_owner'
  end
  issues << "missing audit: #{article.article_key}:#{version.locale}" unless matching_audit.size == 1
  issues << "wrong status: #{article.article_key}:#{version.locale}" unless version.status == 'approved' &&
    version.approved_at && version.approved_by && version.active_on?(Date.current)
  issues << "SHA drift: #{article.article_key}:#{version.locale}" unless
    Digest::SHA256.hexdigest(version.body) == row['sha256'] && version.sha256 == row['sha256']
  issues << "chunk drift: #{article.article_key}:#{version.locale}" unless
    version.knowledge_chunks.order(:chunk_index).pluck(:sha256) == row.fetch('chunks').map { |c| c['sha256'] }
  { article_key: article.article_key, locale: version.locale, content_sha256: version.sha256,
    chunks: version.knowledge_chunks.count, audit_count: matching_audit.size }
end
state = { status: issues.empty? ? 'PASS_APPROVED_KB_NO_GPU' : 'FAIL',
  articles: KnowledgeArticle.count,
  versions_v1_draft: KnowledgeArticleVersion.where(version_number: 1, status: 'draft').count,
  versions_v2_approved: KnowledgeArticleVersion.where(version_number: 2, status: 'approved').count,
  approved_chunks: checks.sum { |item| item[:chunks] },
  embeddings: KnowledgeChunkEmbedding.count,
  source_sha256: Digest::SHA256.file(proposal_path).hexdigest,
  checks: checks, issues: issues }
puts JSON.pretty_generate(state)
raise 'approval checkpoint failed' unless issues.empty? && state[:articles] == 100 &&
  state[:versions_v1_draft] == 200 && state[:versions_v2_approved] == 12 &&
  state[:approved_chunks] == 84 && state[:embeddings] == 0
