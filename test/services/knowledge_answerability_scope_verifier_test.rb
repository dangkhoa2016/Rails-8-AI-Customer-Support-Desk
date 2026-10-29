# frozen_string_literal: true
require 'test_helper'

class KnowledgeAnswerabilityScopeVerifierTest < ActiveSupport::TestCase
  setup do
    @tf = Organization.create!(slug: 'answerability-test-tf', name: 'Scope Test TF',
      vertical:'b2b_saas', currency:'USD')
    @nm = Organization.create!(slug: 'answerability-test-nm', name:'Scope Test NM',
      vertical:'ecommerce',currency:'VND')
  end

  def fake_reranker(scores)
    Struct.new(:model_id,:model_revision,:values,:documents,:calls) do
      def score(query:,documents:)
        self.documents = documents
        self.calls += 1
        values
      end
    end.new(ModalRerankerClient::MODEL_ID,ModalRerankerClient::MODEL_REVISION,scores,nil,0)
  end

  def hit(key)
    KnowledgeRerankedRetrieval::Result.new(article_key:key, rerank_score:9.0,
      content:'approved synthetic text', citation:"#{key}@en:v2#chunk-0")
  end

  test 'load pinned scope matrix with independent conservative margin' do
    gate=KnowledgeAnswerabilityScopeVerifier.pilot
    assert_in_delta 5.05078125,gate.threshold,0.0000001
    assert gate.threshold > 3.6171875
  end

  test 'same-tenant same-language probes, only one extra call and no user input in policy' do
    KnowledgeArticle.create!(organization:@tf,article_key:'TF-KB-012',
      category:'test',audience:'public',policy_refs:[])
    gate=KnowledgeAnswerabilityScopeVerifier.pilot
    fake=fake_reranker([8.0,3.0,2.0,1.0,-3.0,-4.0,-5.0,-2.0])
    assert gate.supports?(query:'Invoice paid but activation did not occur',
      hit:hit('TF-KB-012'),locale:'en',organization:@tf,reranker_client:fake)
    assert_equal 1,fake.calls
    assert_equal 8,fake.documents.length
    assert fake.documents.first.include?('invoice')
    refute fake.documents.any? { |doc| doc.include?('NovaMart') }
  end

  test 'off-topic close question abstains despite strong text overlap' do
    KnowledgeArticle.create!(organization:@nm,article_key:'NM-KB-020',
      category:'test',audience:'public',policy_refs:[])
    gate=KnowledgeAnswerabilityScopeVerifier.pilot
    fake=fake_reranker([6.0,5.0,2.0,1.0,9.0,-2.0,0.0,1.0])
    refute gate.supports?(query:'Can I schedule the exact courier hour?',
      hit:hit('NM-KB-020'),locale:'en',organization:@nm,reranker_client:fake)
    assert_equal 1,fake.calls
  end

  test 'cross-tenant article is rejected before reranker GPU' do
    KnowledgeArticle.create!(organization:@tf,article_key:'TF-KB-012',
      category:'test',audience:'public',policy_refs:[])
    fake=fake_reranker(Array.new(8,1.0))
    assert_raises(SecurityError) do
      KnowledgeAnswerabilityScopeVerifier.pilot.supports?(
        query:'Synthetic invoice paid question',hit:hit('TF-KB-012'),
        locale:'en',organization:@nm,reranker_client:fake)
    end
    assert_equal 0,fake.calls
  end

  test 'pilot corpus validation fails before model execution in clean test database' do
    assert_raises(IOError) do
      KnowledgeAnswerabilityScopeVerifier.pilot.validate!(organization:@tf,locale:'en')
    end
  end

  test 'reranker score shape invalid must not be treated as sufficient evidence' do
    KnowledgeArticle.create!(organization:@tf,article_key:'TF-KB-012',
      category:'test',audience:'public',policy_refs:[])
    gate=KnowledgeAnswerabilityScopeVerifier.pilot
    assert_raises(IOError) do
      gate.supports?(query:'Paid invoice synthetic query',hit:hit('TF-KB-012'),
        locale:'en',organization:@tf,reranker_client:fake_reranker([8.5]))
    end
  end
end
