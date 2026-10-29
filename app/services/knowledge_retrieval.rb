# Source-only retrieval: never sends instructions to Modal and never leaks draft/expired KB.
# No vector search is claimed. PostgreSQL built-in tsvector is the current M2 fallback.
class KnowledgeRetrieval
  Result = Struct.new(:article_key, :article_version_id, :chunk_index, :content, :citation,
                      :policy_refs, :sha256, :locale, keyword_init: true)

  def self.search(organization:, role:, query:, locale:, as_of: Date.current, limit: 8)
    raise ArgumentError, 'untrusted tenant' unless organization.is_a?(Organization) && organization.persisted?
    return [] unless %w[vi en].include?(locale.to_s)
    return [] unless %w[customer viewer agent admin owner].include?(role.to_s)
    q = query.to_s.strip[0, 300]
    return [] if q.size < 2
    aud = %w[admin owner agent].include?(role.to_s) ? %w[public agent] : ['public']

    scope = KnowledgeChunk.joins(knowledge_article_version: :knowledge_article)
      .where(organization_id: organization.id)
      .where(knowledge_article_versions: { organization_id: organization.id, locale: locale,
                                          status: 'approved', policy_version: organization.policy_version })
      .where(knowledge_articles: { organization_id: organization.id, audience: aud })
      .where('knowledge_article_versions.approved_by IS NOT NULL AND knowledge_article_versions.approved_at IS NOT NULL')
      .where('knowledge_article_versions.effective_from <= ?', as_of)
      .where('knowledge_article_versions.effective_to IS NULL OR knowledge_article_versions.effective_to >= ?', as_of)

    # This is parameterized; no user-provided SQL or dynamic tenant identifiers.
    term = "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
    scope = scope.where("to_tsvector('simple', knowledge_chunks.body) @@ plainto_tsquery('simple', ?) OR knowledge_chunks.body ILIKE ? OR knowledge_article_versions.title ILIKE ?", q, term, term)
    scope.order('knowledge_articles.article_key ASC, knowledge_chunks.chunk_index ASC').limit([limit.to_i, 20].min).map do |chunk|
      version = chunk.knowledge_article_version
      article = version.knowledge_article
      Result.new(article_key: article.article_key, article_version_id: version.id,
                 chunk_index: chunk.chunk_index, content: chunk.body,
                 citation: "#{article.article_key}@#{version.locale}:v#{version.version_number}#chunk-#{chunk.chunk_index}",
                 policy_refs: article.policy_refs, sha256: chunk.sha256, locale: version.locale)
    end
  end
end
