# frozen_string_literal: true
require 'test_helper'

class KnowledgeClaimEvidencePilotTest < ActiveSupport::TestCase
  setup do
    @org=Organization.create!(slug:'teamflow-cloud',name:'Synthetic Claim Tenant',
      vertical:'b2b_saas',currency:'USD')
    @embed=Struct.new(:model_id,:model_revision).new(
      ModalEmbeddingClient::MODEL_ID, ModalEmbeddingClient::MODEL_REVISION)
    @rerank=Struct.new(:model_id,:model_revision).new(
      ModalRerankerClient::MODEL_ID, ModalRerankerClient::MODEL_REVISION)
    @gate=Object.new
    def @gate.validate!; true; end
    def @gate.filter(hits); hits.select{|h| h.rerank_score>=7.421875}; end
    @scope=Object.new
    def @scope.validate!(organization:,locale:); true; end
    def @scope.supports?(query:,hit:,locale:,organization:,reranker_client:)
      !query.include?('guarantee')
    end
  end

  def claim(id,txt)
    KnowledgeClaimEvidencePilot::Claim.new(id:id,text:txt)
  end

  def search_stub(callback)
    orig=KnowledgeRerankedRetrieval.method(:search)
    KnowledgeRerankedRetrieval.define_singleton_method(:search,&callback)
    yield
  ensure
    KnowledgeRerankedRetrieval.define_singleton_method(:search,orig)
  end

  test 'human-supplied atomic claims generate partial candidates, never an autonomous answer' do
    good=KnowledgeRerankedRetrieval::Result.new(article_key:'TF-KB-012',
      citation:'TF-KB-012@en:v2#chunk-0',article_version_id:33,
      sha256:'a'*64,rerank_score:9.0)
    calls=[]
    search_stub(->(**opts){calls << opts; [good]}) do
      r=KnowledgeClaimEvidencePilot.evaluate(
        organization:@org,role:'agent',locale:'en',
        claims:[claim('C1','Must a paid invoice match an activation event?'),
          claim('C2','Can support guarantee a thirty minute fix?')],
        embedding_client:@embed,reranker_client:@rerank,privacy_reviewed:true,
        relevance_gate:@gate,scope_verifier:@scope)
      assert_equal 'partial_candidates',r[:state]
      assert_equal 2,r[:claim_count]
      assert_equal 1,r[:candidate_count]
      assert_equal 'NO_AUTONOMOUS_ANSWER_HUMAN_REVIEW_REQUIRED',r[:decision]
      assert_equal 'evidence_candidate_human_review_required',r[:results][0][:status]
      assert_equal 'abstain_no_qualified_evidence',r[:results][1][:status]
      assert_equal 2,calls.size
      assert calls.all?{|x| x[:organization].id==@org.id && x[:role]=='agent' && x[:query_privacy_reviewed]}
    end
  end

  test 'privacy review, permission, cardinality and PII fail before GPU' do
    cb=->(**_opts){ raise 'GPU should never be called' }
    search_stub(cb) do
      assert_raises(SecurityError) { KnowledgeClaimEvidencePilot.evaluate(
        organization:@org,role:'agent',locale:'en',
        claims:[claim('C1','Synthetic approved invoice question')],
        embedding_client:@embed,reranker_client:@rerank,privacy_reviewed:false,
        relevance_gate:@gate,scope_verifier:@scope)}
      assert_raises(ArgumentError) { KnowledgeClaimEvidencePilot.evaluate(
        organization:@org,role:'viewer',locale:'en',
        claims:[claim('C1','Synthetic approved invoice question')],
        embedding_client:@embed,reranker_client:@rerank,privacy_reviewed:true,
        relevance_gate:@gate,scope_verifier:@scope)}
      assert_raises(SecurityError) { KnowledgeClaimEvidencePilot.evaluate(
        organization:@org,role:'agent',locale:'en',
        claims:[claim('C1','Contact customer@example.com for this bill')],
        embedding_client:@embed,reranker_client:@rerank,privacy_reviewed:true,
        relevance_gate:@gate,scope_verifier:@scope)}
      assert_raises(ArgumentError) { KnowledgeClaimEvidencePilot.evaluate(
        organization:@org,role:'agent',locale:'en',claims:[],
        embedding_client:@embed,reranker_client:@rerank,privacy_reviewed:true,
        relevance_gate:@gate,scope_verifier:@scope)}
    end
  end

  test 'preflight fails closed before any model request' do
    def @scope.validate!(organization:,locale:);raise IOError,'stale';end
    search_stub(->(**_opts){raise 'GPU was called despite stale corpus'}) do
      assert_raises(IOError) { KnowledgeClaimEvidencePilot.evaluate(
        organization:@org,role:'agent',locale:'en',
        claims:[claim('C1','Synthetic paid invoice and activation question')],
        embedding_client:@embed,reranker_client:@rerank,privacy_reviewed:true,
        relevance_gate:@gate,scope_verifier:@scope)}
    end
  end
end
