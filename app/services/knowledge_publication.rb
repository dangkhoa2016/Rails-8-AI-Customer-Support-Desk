# Human-controlled version approval. The requester MUST be a Rails authenticated tenant member.
class KnowledgePublication
  def self.approve!(version:, membership:, reviewer_notes:, review_attested:)
    raise SecurityError, 'not authorized to approve KB' unless %w[owner admin].include?(membership.role)
    raise SecurityError, 'cross-tenant approval' unless membership.organization_id == version.organization_id
    raise ArgumentError, 'explicit editorial attestation required' unless review_attested == true
    note = reviewer_notes.to_s.strip
    raise ArgumentError, 'editorial notes required (15-2000 chars)' unless note.length.between?(15, 2000)

    article = version.knowledge_article
    article.with_lock do
      version.reload
      return version if version.status == 'approved'
      raise ArgumentError, 'only draft content can be approved' unless version.status == 'draft'
      latest_number = KnowledgeArticleVersion.where(organization_id: version.organization_id,
        knowledge_article_id: article.id, locale: version.locale).maximum(:version_number)
      raise ArgumentError, 'review the latest KB version instead of an older draft' unless version.version_number == latest_number
      raise ArgumentError, 'empty KB content' if version.body.blank?
      raise ArgumentError, 'content digest mismatch' unless Digest::SHA256.hexdigest(version.body) == version.sha256
      raise ArgumentError, 'policy mismatch' unless version.policy_version == membership.organization.policy_version
      raise ArgumentError, 'incomplete chunks' unless version.knowledge_chunks.order(:chunk_index).pluck(:body).join == version.body

      KnowledgeArticleVersion.where(organization_id: version.organization_id,
        knowledge_article_id: article.id, locale: version.locale, status: 'approved')
        .where.not(id: version.id).update_all(status: 'superseded', updated_at: Time.current)
      version.update!(status: 'approved', approved_by: membership.user_id, approved_at: Time.current)
    end
    version
  end
end
