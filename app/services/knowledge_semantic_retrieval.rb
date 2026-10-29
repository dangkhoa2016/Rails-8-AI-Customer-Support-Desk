# frozen_string_literal: true
# Exact vector retrieval. This service does not call Modal: the caller must obtain
# a privacy-reviewed 2560-dimension query embedding separately. Do not send raw
# tickets, names, email addresses, or customer records to the embedding provider.
class KnowledgeSemanticRetrieval
  DIMENSIONS = 2560
  Result = Struct.new(:article_key, :article_version_id, :chunk_index, :content,
    :citation, :policy_refs, :sha256, :locale, :cosine_distance, keyword_init: true)

  def self.search(organization:, role:, embedding:, locale:, model_id:, model_revision:,
                  as_of: Date.current, limit: 8)
    raise ArgumentError, 'untrusted tenant' unless organization.is_a?(Organization) && organization.persisted?
    raise ArgumentError, 'invalid role' unless %w[customer viewer agent admin owner].include?(role.to_s)
    return [] unless %w[vi en].include?(locale.to_s)
    raise ArgumentError, 'unversioned model' unless model_id.to_s.match?(/\A[a-zA-Z0-9_\/.-]+\z/) &&
      model_revision.to_s.match?(/\A[a-zA-Z0-9_.-]{7,128}\z/)
    raise ArgumentError, 'invalid vector' unless embedding.is_a?(Array) &&
      embedding.length == DIMENSIONS && embedding.all? { |v| v.is_a?(Numeric) && v.finite? }
    magnitude = embedding.sum { |v| v.to_f**2 }
    raise ArgumentError, 'zero magnitude vector' unless magnitude.positive?
    raise ArgumentError, 'invalid date' unless as_of.is_a?(Date)

    audience = %w[agent admin owner].include?(role.to_s) ? %w[public agent] : ['public']
    vector_string = '[' + embedding.map { |v| format('%.10g', v) }.join(',') + ']'
    # Values interpolated into ORDER BY are ONLY finite floats formatted above,
    # then SQL-quoted by ActiveRecord; tenant/ACL filters are regular bind params.
    order_sql = ActiveRecord::Base.sanitize_sql_array([
      'knowledge_chunk_embeddings.embedding <=> ?::vector ASC, knowledge_chunks.id ASC', vector_string
    ])

    rows = KnowledgeChunk.joins(knowledge_article_version: :knowledge_article)
      .joins('INNER JOIN knowledge_chunk_embeddings ON knowledge_chunk_embeddings.knowledge_chunk_id = knowledge_chunks.id AND knowledge_chunk_embeddings.organization_id = knowledge_chunks.organization_id')
      .where(organization_id: organization.id)
      .where(knowledge_chunk_embeddings: { organization_id: organization.id,
        model_id: model_id, model_revision: model_revision })
      .where('knowledge_chunk_embeddings.content_sha256 = knowledge_chunks.sha256')
      .where(knowledge_article_versions: { organization_id: organization.id, locale: locale.to_s,
        status: 'approved', policy_version: organization.policy_version })
      .where(knowledge_articles: { organization_id: organization.id, audience: audience })
      .where('knowledge_article_versions.approved_by IS NOT NULL AND knowledge_article_versions.approved_at IS NOT NULL')
      .where('knowledge_article_versions.effective_from <= ?', as_of)
      .where('knowledge_article_versions.effective_to IS NULL OR knowledge_article_versions.effective_to >= ?', as_of)
      .select('knowledge_chunks.*, knowledge_chunk_embeddings.embedding <=> ' +
        ActiveRecord::Base.connection.quote(vector_string) + '::vector AS cosine_distance')
      .order(Arel.sql(order_sql))
      .limit([[limit.to_i, 1].max, 20].min)

    rows.map do |chunk|
      version = chunk.knowledge_article_version
      article = version.knowledge_article
      Result.new(article_key: article.article_key, article_version_id: version.id,
        chunk_index: chunk.chunk_index, content: chunk.body,
        citation: "#{article.article_key}@#{version.locale}:v#{version.version_number}#chunk-#{chunk.chunk_index}",
        policy_refs: article.policy_refs, sha256: chunk.sha256, locale: version.locale,
        cosine_distance: chunk.attributes.fetch('cosine_distance').to_f)
    end
  end
end
