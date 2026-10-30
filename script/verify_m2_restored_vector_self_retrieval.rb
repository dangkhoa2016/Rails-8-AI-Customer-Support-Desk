# frozen_string_literal: true
# Structural pgvector self-retrieval (document vectors, not fresh query embeddings).
# This does NOT measure semantic relevance or invoke a GPU.
require 'json'
require 'time'
require 'digest'
raise 'development synthetic only' unless Rails.env.development? && ENV['M1_SYNTHETIC_DEMO'] == 'YES'
raise 'expected restored vectors' unless KnowledgeChunkEmbedding.count == 84
results = KnowledgeArticleVersion.includes(:knowledge_article, :organization).where(
  version_number: 2, status: 'approved').order(:organization_id, :locale, :id).map do |version|
  chunk = version.knowledge_chunks.order(:chunk_index).first
  raise 'approved KB missing chunk' unless chunk
  vector_row = KnowledgeChunkEmbedding.find_by!(organization_id: version.organization_id,
    knowledge_chunk_id: chunk.id,
    model_id: ModalEmbeddingClient::MODEL_ID,
    model_revision: ModalEmbeddingClient::MODEL_REVISION)
  vector = vector_row.embedding.to_s.delete_prefix('[').delete_suffix(']').split(',').map { |s| Float(s) }
  raise 'invalid source vector width' unless vector.size == 2560 && vector.all?(&:finite?)
  hits = KnowledgeSemanticRetrieval.search(
    organization: version.organization, role: 'agent', embedding: vector,
    locale: version.locale, model_id: vector_row.model_id,
    model_revision: vector_row.model_revision, as_of: Date.new(2026, 10, 29), limit: 5)
  first = hits.first
  raise "self nearest neighbor mismatch #{version.id}" unless first &&
    first.article_version_id == version.id &&
    first.chunk_index == chunk.chunk_index &&
    first.sha256 == chunk.sha256
  raise 'invalid distance' unless first.cosine_distance.between?(0, 0.0001)
  raise 'cross tenant or language result' unless hits.all? { |h|
    ver = KnowledgeArticleVersion.find(h.article_version_id)
    ver.organization_id == version.organization_id && ver.locale == version.locale &&
      ver.status == 'approved' && ver.version_number == 2
  }
  {tenant: version.organization.slug, locale: version.locale,
    article_key: version.knowledge_article.article_key,
    top1: first.citation, self_cosine_distance: first.cosine_distance,
    hits: hits.length}
end
raise '12 approved version checks required' unless results.length == 12
puts JSON.pretty_generate(status: 'PASS_ARCHIVED_DOCUMENT_VECTOR_SELF_RETRIEVAL_NO_GPU',
  source: 'restored frozen M2 document embeddings',
  semantic_answerability_claim: false, new_query_embedding: false,
  model_inference: 'NOT_RUN', checks: results.length, results: results)
