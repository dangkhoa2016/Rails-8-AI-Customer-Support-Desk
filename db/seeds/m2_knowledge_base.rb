# frozen_string_literal: true
# Idempotent M2 importer. Never silently overwrites a reviewed/published version.
# Prerequisite: M1 organizations exist. Usage: bin/rails runner db/seeds/m2_knowledge_base.rb
require 'json'
require 'digest'

root = Rails.root
path = root.join('data/m2/knowledge_drafts.json')
payload = JSON.parse(File.read(path))
blueprint_sha = Digest::SHA256.file(root.join('docs/RAILS8_AI_SUPPORT_DESK_CANONICAL_BLUEPRINT_2026-10-28.json')).hexdigest
raise 'Source blueprint hash mismatch' unless payload.fetch('source_blueprint_sha256') == blueprint_sha
raise 'KB seed must contain only drafts' unless payload.fetch('publication_status') == 'PENDING_HUMAN_EDITORIAL_APPROVAL'

ActiveRecord::Base.transaction do
  payload.fetch('articles').each do |row|
    org = Organization.find_by!(slug: row.fetch('organization_slug'))
    raise 'Tenant policy version mismatch' unless org.policy_version == payload.fetch('policy_version')
    article = KnowledgeArticle.find_or_initialize_by(organization_id: org.id, article_key: row.fetch('article_key'))
    article.assign_attributes(category: row.fetch('category'), audience: row.fetch('audience'), policy_refs: row.fetch('policy_refs'))
    article.save!
    row.fetch('versions').each do |data|
      version = KnowledgeArticleVersion.find_or_initialize_by(organization_id: org.id, knowledge_article_id: article.id,
        locale: data.fetch('locale'), version_number: data.fetch('version'))
      if version.persisted?
        raise "KB approved/draft content drift: #{article.article_key} #{version.locale}" unless version.sha256 == data.fetch('sha256')
      else
        version.assign_attributes(title: data.fetch('title'), body: data.fetch('body'), status: 'draft',
          effective_from: data.fetch('effective_from'), effective_to: data['effective_to'],
          sha256: data.fetch('sha256'), policy_version: payload.fetch('policy_version'),
          source_blueprint_sha256: blueprint_sha)
        version.save!
      end
      data.fetch('chunks').each do |row_chunk|
        chunk = KnowledgeChunk.find_or_initialize_by(organization_id: org.id,
          knowledge_article_version_id: version.id, chunk_index: row_chunk.fetch('chunk_index'))
        if chunk.persisted?
          raise "KB chunk drift: #{article.article_key}/#{chunk.chunk_index}" unless chunk.sha256 == row_chunk.fetch('sha256')
        else
          chunk.assign_attributes(body: row_chunk.fetch('body'), sha256: row_chunk.fetch('sha256'),
            embedding_status: 'not_generated')
          chunk.save!
        end
      end
    end
  end
end
puts "M2 KB seeded: articles=#{KnowledgeArticle.count}, versions=#{KnowledgeArticleVersion.count}, chunks=#{KnowledgeChunk.count}, approved=#{KnowledgeArticleVersion.where(status: 'approved').count}"
