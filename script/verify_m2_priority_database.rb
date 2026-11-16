# frozen_string_literal: true
# Read-only verification of M2 v1 baseline and 12 editorial v2 drafts.
require 'json'
require 'digest'
root = Rails.root
base = JSON.parse(File.read(root.join('data/m2/knowledge_drafts.json')))
proposals = JSON.parse(File.read(root.join('review/m2_priority_editorial_proposals_20261029.json')))
raise 'canonical source drift' unless proposals.fetch('canonical_sha256') ==
  Digest::SHA256.file(root.join('data/policy/canonical_blueprint.json')).hexdigest
raise 'base source drift' unless proposals.fetch('source_m2_sha256') ==
  Digest::SHA256.file(root.join('data/m2/knowledge_drafts.json')).hexdigest
errors = []
checked_v1 = 0
checked_v2 = 0
base.fetch('articles').each do |article_data|
  org = Organization.find_by!(slug: article_data.fetch('organization_slug'))
  article = KnowledgeArticle.find_by!(organization: org, article_key: article_data.fetch('article_key'))
  article_data.fetch('versions').each do |record|
    v = KnowledgeArticleVersion.find_by!(organization: org, knowledge_article: article,
      locale: record.fetch('locale'), version_number: 1)
    errors << "v1 digest changed #{article.article_key}/#{record['locale']}" unless
      v.sha256 == record.fetch('sha256') && Digest::SHA256.hexdigest(v.body) == v.sha256
    errors << "v1 chunk drift #{article.article_key}/#{record['locale']}" unless
      v.knowledge_chunks.order(:chunk_index).pluck(:body).join == v.body
    checked_v1 += 1
  end
end
proposals.fetch('revisions').each do |record|
  org = Organization.find_by!(slug: record.fetch('organization_slug'))
  article = KnowledgeArticle.find_by!(organization: org, article_key: record.fetch('article_key'))
  v = KnowledgeArticleVersion.find_by!(organization: org, knowledge_article: article,
    locale: record.fetch('locale'), version_number: 2)
  errors << "v2 status #{article.article_key}/#{record['locale']}" unless
    v.status == 'draft' && v.approved_at.nil? && v.approved_by.nil?
  errors << "v2 digest #{article.article_key}/#{record['locale']}" unless
    v.sha256 == record.fetch('sha256') && Digest::SHA256.hexdigest(v.body) == v.sha256
  errors << "v2 chunks #{article.article_key}/#{record['locale']}" unless
    v.knowledge_chunks.order(:chunk_index).pluck(:sha256) ==
    record.fetch('chunks').map { |chunk| chunk.fetch('sha256') } &&
    v.knowledge_chunks.order(:chunk_index).pluck(:body).join == v.body
  checked_v2 += 1
end
summary = {
  status: errors.empty? ? 'PASS_DB_EDITORIAL_DRAFTS_ONLY' : 'FAIL',
  v1_checked: checked_v1, v2_checked: checked_v2,
  articles: KnowledgeArticle.count, versions: KnowledgeArticleVersion.count,
  chunks: KnowledgeChunk.count,
  approved: KnowledgeArticleVersion.where(status: 'approved').count,
  embeddings: KnowledgeChunkEmbedding.count,
  canonical_policy_version: base.fetch('policy_version'),
  errors: errors
}
puts JSON.pretty_generate(summary)
raise 'M2 editorial database verification failed' unless errors.empty? &&
  checked_v1 == 200 && checked_v2 == 12 && summary[:articles] == 100 &&
  summary[:versions] == 212 && summary[:chunks] == 1484 &&
  summary[:approved] == 0 && summary[:embeddings] == 0
