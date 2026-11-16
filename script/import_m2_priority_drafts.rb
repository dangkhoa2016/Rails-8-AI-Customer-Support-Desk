# frozen_string_literal: true
# Adds exactly 12 v2 DRAFTS. Keeps all 200 v1 versions and M0/M1 unchanged.
# Run explicitly in synthetic dev only:
#   M2_PRIORITY_IMPORT=YES bin/rails runner script/import_m2_priority_drafts.rb
require 'json'
require 'digest'
raise 'Synthetic development only' unless Rails.env.development? &&
  ENV['M1_SYNTHETIC_DEMO'] == 'YES' &&
  ENV['M2_PRIORITY_IMPORT'] == 'YES'

root = Rails.root
source_path = root.join('data/m2/knowledge_drafts.json')
proposal = JSON.parse(File.read(root.join('review/m2_priority_editorial_proposals_20261029.json')))
canonical_path = root.join('data/policy/canonical_blueprint.json')
raise 'source mismatch' unless proposal.fetch('source_m2_sha256') == Digest::SHA256.file(source_path).hexdigest
raise 'policy source mismatch' unless proposal.fetch('canonical_sha256') == Digest::SHA256.file(canonical_path).hexdigest
raise 'wrong policy version' unless proposal.fetch('policy_version') == '1.0.0'
revisions = proposal.fetch('revisions')
raise 'expected 12 v2 drafts' unless revisions.length == 12 &&
  revisions.map { |v| [v.fetch('article_key'), v.fetch('locale')] }.uniq.length == 12

created = 0
ActiveRecord::Base.transaction do
  revisions.each do |row|
    org = Organization.find_by!(slug: row.fetch('organization_slug'))
    raise 'wrong tenant policy' unless org.policy_version == proposal.fetch('policy_version')
    article = KnowledgeArticle.find_by!(organization: org, article_key: row.fetch('article_key'))
    raise 'policy refs changed' unless article.policy_refs == row.fetch('policy_refs')
    old_version = KnowledgeArticleVersion.find_by!(
      organization: org, knowledge_article: article, locale: row.fetch('locale'), version_number: 1)
    raise 'v1 source drift' unless old_version.sha256 == row.fetch('based_on_v1_sha256')
    raise 'not draft' unless row.fetch('status') == 'draft' && row['approved_by'].nil? && row['approved_at'].nil?
    text = row.fetch('body')
    raise 'v2 hash mismatch' unless Digest::SHA256.hexdigest(text) == row.fetch('sha256')
    chunks = row.fetch('chunks')
    raise 'invalid chunks' unless chunks.length == 7 &&
      chunks.map { |c| c.fetch('chunk_index') } == (0..6).to_a &&
      chunks.map { |c| c.fetch('body') }.join == text &&
      chunks.all? { |c| Digest::SHA256.hexdigest(c.fetch('body')) == c.fetch('sha256') }
    v2 = KnowledgeArticleVersion.find_or_initialize_by(
      organization: org, knowledge_article: article, locale: row.fetch('locale'), version_number: 2)
    if v2.persisted?
      raise 'v2 previously edited: stop and review' unless v2.sha256 == row.fetch('sha256') &&
        v2.status == 'draft' && v2.knowledge_chunks.order(:chunk_index).pluck(:sha256) ==
          chunks.map { |c| c['sha256'] }
      next
    end
    v2.assign_attributes(title: row.fetch('title'), body: text, sha256: row.fetch('sha256'),
      status: 'draft', approved_by: nil, approved_at: nil, effective_from: row.fetch('effective_from'),
      effective_to: row['effective_to'], policy_version: proposal.fetch('policy_version'),
      source_blueprint_sha256: proposal.fetch('canonical_sha256'))
    v2.save!
    chunks.each do |c|
      KnowledgeChunk.create!(organization: org, knowledge_article_version: v2,
        chunk_index: c.fetch('chunk_index'), body: c.fetch('body'), sha256: c.fetch('sha256'),
        embedding_status: 'not_generated')
    end
    created += 1
  end
end
puts JSON.generate({ source: 'M2_EDITORIAL_PRIORITY_V2', created_drafts: created,
  existing_or_new_v2: revisions.length,
  v1_versions: KnowledgeArticleVersion.where(version_number: 1).count,
  v2_versions: KnowledgeArticleVersion.where(version_number: 2).count,
  approved: KnowledgeArticleVersion.where(status: 'approved').count })
