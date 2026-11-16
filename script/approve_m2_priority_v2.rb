# frozen_string_literal: true
# Records explicit USER approval of the 12 previewed VI/EN drafts, delegated through
# this session. Audit actor is a SYNTHETIC DEMO owner, not a person's login.
# No customer/business writes. Never auto-approve any other KB version.
require 'json'
require 'digest'
raise 'synthetic development only' unless Rails.env.development? && ENV['M1_SYNTHETIC_DEMO'] == 'YES'
root = Rails.root
source = root.join('review/m2_priority_editorial_proposals_20261029.json')
proposal = JSON.parse(File.read(source))
raise 'invalid source checksum' unless proposal.fetch('source_m2_sha256') == Digest::SHA256.file(root.join('data/m2/knowledge_drafts.json')).hexdigest
raise 'policy baseline drift' unless proposal.fetch('canonical_sha256') == Digest::SHA256.file(root.join('data/policy/canonical_blueprint.json')).hexdigest
versions = proposal.fetch('revisions')
raise 'expected exactly 12 VI/EN versions' unless versions.length == 12 && versions.map { |v| [v['article_key'], v['locale']] }.uniq.size == 12
prepared = versions.map do |row|
  org = Organization.find_by!(slug: row.fetch('organization_slug'))
  article = KnowledgeArticle.find_by!(organization: org, article_key: row.fetch('article_key'))
  version = KnowledgeArticleVersion.find_by!(organization: org, knowledge_article: article,
    locale: row.fetch('locale'), version_number: 2)
  raise 'source version mismatch' unless version.sha256 == row.fetch('sha256') && Digest::SHA256.hexdigest(version.body) == version.sha256
  raise 'policy mismatch' unless version.policy_version == org.policy_version && article.policy_refs == row.fetch('policy_refs')
  raise 'invalid current status' unless %w[draft approved].include?(version.status)
  owner = Membership.find_by!(organization: org, role: 'owner')
  raise 'demo owner membership unavailable' unless owner.user.email.end_with?('@example.test')
  [org, article, version, owner]
end
status = prepared.map { |org, article, version, _| { tenant: org.slug, article: article.article_key,
  locale: version.locale, sha256: version.sha256, status: version.status } }
if ENV['M2_APPROVE_BATCH'] != 'YES'
  puts JSON.pretty_generate({ mode: 'DRY_RUN', would_review: status, approved: 0 })
  exit(0)
end
note = 'Project owner reviewed VI/EN static preview and approved the content on 2026-10-29; action delegated to synthetic demo owner by chat instruction.'
created = 0
ActiveRecord::Base.transaction do
  prepared.each do |org, article, version, owner|
    next if version.status == 'approved' # Subsequent re-runs do not duplicate audits.
    KnowledgePublication.approve!(version: version, membership: owner,
      reviewer_notes: note, review_attested: true)
    AuditEvent.create!(organization_id: org.id, actor_user_id: owner.user_id,
      action: 'kb.version_approved', metadata: { article_key: article.article_key,
        locale: version.locale, version: 2, sha256: version.sha256, editorial_attested: true,
        reviewer_notes: note, approval_origin: 'user_chat_confirmation_2026_10_29',
        audit_actor_kind: 'synthetic_demo_tenant_owner', delegated_execution: true })
    created += 1
  end
end
puts JSON.pretty_generate({mode: 'APPROVAL_RECORDED', newly_approved: created,
  v2_approved: KnowledgeArticleVersion.where(version_number: 2, status: 'approved').count,
  all_versions_approved: KnowledgeArticleVersion.where(status: 'approved').count,
  v1_versions: KnowledgeArticleVersion.where(version_number: 1).count,
  embedding_vectors: KnowledgeChunkEmbedding.count, approval_origin: 'project_owner_chat_confirmation',
  actor_disclosure: 'synthetic demo owner - delegated operator execution' })
