# frozen_string_literal: true
require 'test_helper'
require 'digest'

# Deterministic synthetic vectors ONLY. No Modal or GPU is called.
class SemanticKbSecurityTest < ActiveSupport::TestCase
  MODEL_ID = ModalEmbeddingClient::MODEL_ID
  REV = ModalEmbeddingClient::MODEL_REVISION
  def setup
    @tf = Organization.create!(slug: 'vector-tf', name: 'Vector TF', vertical: 'b2b_saas', currency: 'USD')
    @nm = Organization.create!(slug: 'vector-nm', name: 'Vector NM', vertical: 'ecommerce', currency: 'VND')
    u = User.create!(email: 'vector-owner@example.test')
    @member = Membership.create!(organization: @tf, user: u, role: 'owner')
    @nm_member = Membership.create!(organization: @nm, user: User.create!(email: 'vector-nm@example.test'), role: 'owner')
    @q = Array.new(2560, 0.0)
    @q[0] = 1.0
  end

  test 'correct tenant and citation only, and revision pinning' do
    create_chunk(@tf, 'TF-VEC', 'approved TF content')
    create_chunk(@nm, 'NM-VEC', 'approved NM content')
    hits = search(@tf, 'agent')
    assert_equal ['TF-VEC'], hits.map(&:article_key)
    assert_match(/TF-VEC@en:v1#chunk-0/, hits.first.citation)
    assert_equal Digest::SHA256.hexdigest('approved TF content'), hits.first.sha256
    assert_empty search(@tf, 'agent', revision: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb')
  end

  test 'draft and agent-only ACL are never bypassed by stored vectors' do
    create_chunk(@tf, 'TF-DRAFT-VEC', 'secret draft', approved: false)
    create_chunk(@tf, 'TF-AGENT-VEC', 'restricted', audience: 'agent')
    assert_empty search(@tf, 'viewer')
    assert_equal ['TF-AGENT-VEC'], search(@tf, 'agent').map(&:article_key)
    assert_equal 1, KnowledgeEmbeddingIngestion.eligible_chunks(organization: @tf).count
  end

  test 'temporal rules and superseded version invalidate stored vectors' do
    create_chunk(@tf, 'TF-EXPIRED', 'old', effective_to: Date.new(2026, 10, 28))
    create_chunk(@tf, 'TF-FUTURE', 'future', effective_from: Date.new(2099, 1, 1))
    v = create_chunk(@tf, 'TF-CURRENT', 'valid')
    assert_equal ['TF-CURRENT'], search(@tf, 'agent').map(&:article_key)
    v.update!(status: 'superseded')
    assert_empty search(@tf, 'agent')
  end

  test 'invalid vector, role and model identity fail closed' do
    assert_raises(ArgumentError) { KnowledgeSemanticRetrieval.search(
      organization: @tf, role: 'agent', embedding: [1.0], locale: 'en',
      model_id: MODEL_ID, model_revision: REV) }
    assert_raises(ArgumentError) { search(@tf, 'system') }
    assert_raises(ArgumentError) { search(@tf, 'agent', revision: '') }
  end

  test 'stale digest row cannot become a citation' do
    create_chunk(@tf, 'TF-TAMPERED', 'original approved text')
    KnowledgeChunkEmbedding.where(organization_id: @tf.id).update_all(content_sha256: 'f' * 64)
    assert_empty search(@tf, 'agent')
  end

  test 'ingestion never sends a draft to the embedding model' do
    approved_version = create_chunk(@tf, 'TF-INGEST-APPROVED', 'approved document')
    create_chunk(@tf, 'TF-INGEST-DRAFT', 'private draft', approved: false)
    KnowledgeChunkEmbedding.where(organization_id: @tf.id).delete_all
    fake = Struct.new(:model_id, :model_revision, :sent) do
      def embed_documents(texts)
        self.sent = texts
        texts.map { [1.0] + Array.new(2559, 0.0) }
      end
    end.new(MODEL_ID, REV, nil)
    outcome = KnowledgeEmbeddingIngestion.ingest!(organization: @tf, client: fake)
    assert_equal ['approved document'], fake.sent
    assert_equal 1, outcome.fetch(:embedded)
    assert_equal approved_version.id, KnowledgeChunkEmbedding.last.knowledge_chunk.knowledge_article_version_id
    assert_equal ['TF-INGEST-APPROVED'], search(@tf, 'agent').map(&:article_key)
  end

  test '4B embedding candidates are tenant-filtered before rerank and citations retained' do
    create_chunk(@tf, 'TF-RERANK-FIRST', 'first approved doc')
    create_chunk(@tf, 'TF-RERANK-SECOND', 'second approved doc')
    create_chunk(@tf, 'TF-RERANK-DRAFT', 'never send private draft', approved: false)
    create_chunk(@nm, 'NM-RERANK-PRIVATE', 'never send other tenant')
    fake_embed = Struct.new(:model_id, :model_revision, :query_embedding) do
      def embed_query(_query); query_embedding; end
    end.new(ModalEmbeddingClient::MODEL_ID, ModalEmbeddingClient::MODEL_REVISION, @q)
    fake_rerank = Struct.new(:model_id, :model_revision, :observed_query, :observed_docs) do
      def score(query:, documents:)
        self.observed_query = query
        self.observed_docs = documents
        documents.map { |doc| doc.include?('second') ? 9.0 : 1.0 }
      end
    end.new(ModalRerankerClient::MODEL_ID, ModalRerankerClient::MODEL_REVISION)
    hits = KnowledgeRerankedRetrieval.search(organization: @tf, role: 'agent', query: 'check plan',
      locale: 'en', embedding_client: fake_embed, reranker_client: fake_rerank,
      query_privacy_reviewed: true)
    assert_equal %w[TF-RERANK-SECOND TF-RERANK-FIRST], hits.map(&:article_key)
    assert_equal ['first approved doc', 'second approved doc'].sort, fake_rerank.observed_docs.sort
    assert_equal 'check plan', fake_rerank.observed_query
    assert_equal [9.0, 1.0], hits.map(&:rerank_score)
    assert hits.all? { |hit| hit.citation.include?('@en:v1#chunk-0') }
  end

  test 'reranker cannot receive query without privacy attestation' do
    fake_embed = Struct.new(:model_id, :model_revision).new(ModalEmbeddingClient::MODEL_ID,
      ModalEmbeddingClient::MODEL_REVISION)
    fake_rerank = Struct.new(:model_id, :model_revision).new(ModalRerankerClient::MODEL_ID,
      ModalRerankerClient::MODEL_REVISION)
    assert_raises(SecurityError) do
      KnowledgeRerankedRetrieval.search(organization: @tf, role: 'agent', query: 'someone@example.com',
        locale: 'en', embedding_client: fake_embed, reranker_client: fake_rerank)
    end
  end

  test 'agent only KB snippets are never sent to reranker for viewer role' do
    create_chunk(@tf, 'TF-RESTRICTED', 'agent private only', audience: 'agent')
    fake_embed = Struct.new(:model_id, :model_revision, :query_embedding) do
      def embed_query(_query); query_embedding; end
    end.new(ModalEmbeddingClient::MODEL_ID, ModalEmbeddingClient::MODEL_REVISION, @q)
    fake_rerank = Struct.new(:model_id, :model_revision, :called) do
      def score(query:, documents:); self.called = true; raise 'unexpected outbound call'; end
    end.new(ModalRerankerClient::MODEL_ID, ModalRerankerClient::MODEL_REVISION, false)
    assert_empty KnowledgeRerankedRetrieval.search(organization: @tf, role: 'viewer',
      query: 'synthetic test query', locale: 'en', embedding_client: fake_embed,
      reranker_client: fake_rerank, query_privacy_reviewed: true)
    assert_equal false, fake_rerank.called
  end

  test 'scope verification refuses stale corpus before any outbound GPU query' do
    fake_embed = Struct.new(:model_id, :model_revision, :called) do
      def embed_query(*); self.called = true; raise 'embedding must never be called'; end
    end.new(ModalEmbeddingClient::MODEL_ID, ModalEmbeddingClient::MODEL_REVISION, false)
    fake_rerank = Struct.new(:model_id, :model_revision, :called) do
      def score(**); self.called = true; raise 'rerank must never be called'; end
    end.new(ModalRerankerClient::MODEL_ID, ModalRerankerClient::MODEL_REVISION, false)
    assert_raises(IOError) do
      KnowledgeRerankedRetrieval.search(
        organization: @tf, role: 'agent', query: 'Synthetic support question',
        locale: 'en', embedding_client: fake_embed, reranker_client: fake_rerank,
        query_privacy_reviewed: true, relevance_gate: KnowledgeRelevanceGate.pilot,
        answerability_verifier: KnowledgeAnswerabilityScopeVerifier.pilot
      )
    end
    assert_equal false, fake_embed.called
    assert_equal false, fake_rerank.called
  end

  test 'stale calibrated corpus fails closed before either Modal request' do
    fake_embed = Struct.new(:model_id, :model_revision, :called) do
      def embed_query(*); self.called = true; raise 'GPU request should not happen'; end
    end.new(ModalEmbeddingClient::MODEL_ID, ModalEmbeddingClient::MODEL_REVISION, false)
    fake_rerank = Struct.new(:model_id, :model_revision, :called) do
      def score(**); self.called = true; raise 'GPU request should not happen'; end
    end.new(ModalRerankerClient::MODEL_ID, ModalRerankerClient::MODEL_REVISION, false)
    assert_raises(IOError) do
      KnowledgeRerankedRetrieval.search(
        organization: @tf, role: 'agent', query: 'Synthetic question about billing',
        locale: 'en', embedding_client: fake_embed, reranker_client: fake_rerank,
        query_privacy_reviewed: true, relevance_gate: KnowledgeRelevanceGate.pilot
      )
    end
    assert_equal false, fake_embed.called
    assert_equal false, fake_rerank.called
  end

  private

  def search(org, role, revision: REV)
    KnowledgeSemanticRetrieval.search(organization: org, role: role, embedding: @q,
      locale: 'en', model_id: MODEL_ID, model_revision: revision)
  end

  def create_chunk(org, key, body, approved: true, audience: 'public',
                   effective_from: Date.new(2026, 10, 28), effective_to: nil)
    member = org == @tf ? @member : @nm_member
    article = KnowledgeArticle.create!(organization: org, article_key: key,
      category: 'test', audience: audience, policy_refs: [])
    version = KnowledgeArticleVersion.create!(organization: org, knowledge_article: article,
      locale: 'en', version_number: 1, title: key, body: body,
      sha256: Digest::SHA256.hexdigest(body), policy_version: org.policy_version,
      source_blueprint_sha256: 'test', effective_from: effective_from,
      effective_to: effective_to, status: approved ? 'approved' : 'draft',
      approved_by: approved ? member.user_id : nil,
      approved_at: approved ? Time.current : nil)
    chunk = KnowledgeChunk.create!(organization: org, knowledge_article_version: version,
      chunk_index: 0, body: body, sha256: Digest::SHA256.hexdigest(body))
    KnowledgeChunkEmbedding.create!(organization: org, knowledge_chunk: chunk,
      model_id: MODEL_ID, model_revision: REV, content_sha256: chunk.sha256,
      embedding: '[' + @q.join(',') + ']', generated_at: Time.current)
    version
  end
end
