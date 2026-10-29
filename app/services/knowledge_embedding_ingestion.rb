# frozen_string_literal: true
require 'digest'

# Explicit ingestion only. Drafts, stale policy versions, wrong tenant,
# future and expired content are NEVER sent to Modal.
class KnowledgeEmbeddingIngestion
  def self.eligible_chunks(organization:, as_of: Date.current)
    raise ArgumentError, 'untrusted tenant' unless organization.is_a?(Organization) && organization.persisted?
    KnowledgeChunk.joins(knowledge_article_version: :knowledge_article)
      .where(organization_id: organization.id)
      .where(knowledge_article_versions: { organization_id: organization.id,
        status: 'approved', policy_version: organization.policy_version })
      .where(knowledge_articles: { organization_id: organization.id })
      .where('knowledge_article_versions.approved_by IS NOT NULL AND knowledge_article_versions.approved_at IS NOT NULL')
      .where('knowledge_article_versions.effective_from <= ?', as_of)
      .where('knowledge_article_versions.effective_to IS NULL OR knowledge_article_versions.effective_to >= ?', as_of)
      .order('knowledge_chunks.id ASC')
  end

  def self.ingest!(organization:, client:, as_of: Date.current, max_chunks: 8)
    raise ArgumentError, 'invalid max_chunks' unless max_chunks.to_i.between?(1, 8)
    scope = eligible_chunks(organization: organization, as_of: as_of)
    scope = scope.where.not(id: KnowledgeChunkEmbedding.where(organization_id: organization.id,
      model_id: client.model_id, model_revision: client.model_revision).select(:knowledge_chunk_id))
    remaining_before = scope.count
    candidates = scope.limit(max_chunks).to_a
    return { embedded: 0, eligible_remaining: 0 } if candidates.empty?

    candidates.each do |chunk|
      v = chunk.knowledge_article_version
      raise SecurityError, 'KB content digest mismatch' unless Digest::SHA256.hexdigest(chunk.body) == chunk.sha256
      raise SecurityError, 'KB version body mismatch' unless Digest::SHA256.hexdigest(v.body) == v.sha256 &&
        v.knowledge_chunks.order(:chunk_index).pluck(:body).join == v.body
    end

    # External call OUTSIDE the DB transaction; no credentials are logged.
    vectors = client.embed_documents(candidates.map(&:body))
    raise IOError, 'embedding count mismatch' unless vectors.length == candidates.length
    inserted = 0
    candidates.zip(vectors).each do |chunk, vector|
      raise IOError, 'invalid embedding dimension' unless vector.is_a?(Array) && vector.length == 2560 &&
        vector.all? { |v| v.is_a?(Numeric) && v.finite? }
      literal = '[' + vector.map { |f| format('%.10g', f) }.join(',') + ']'
      KnowledgeChunk.transaction do
        chunk.reload
        version = chunk.knowledge_article_version.reload
        raise SecurityError, 'KB approval or date changed during ingestion' unless
          version.active_on?(as_of) && version.policy_version == organization.policy_version &&
          version.organization_id == organization.id && chunk.organization_id == organization.id &&
          Digest::SHA256.hexdigest(chunk.body) == chunk.sha256
        e = KnowledgeChunkEmbedding.find_or_initialize_by(organization_id: organization.id,
          knowledge_chunk_id: chunk.id, model_id: client.model_id, model_revision: client.model_revision)
        if e.persisted?
          raise SecurityError, 'embedding drift' unless e.content_sha256 == chunk.sha256
        else
          e.content_sha256 = chunk.sha256
          e.embedding = literal
          e.generated_at = Time.current
          e.save!
          inserted += 1
        end
      end
    end
    { embedded: inserted, eligible_remaining: [remaining_before - inserted, 0].max }
  end
end
