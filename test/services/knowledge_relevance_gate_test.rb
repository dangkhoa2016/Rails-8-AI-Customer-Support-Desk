# frozen_string_literal: true
require 'test_helper'

class KnowledgeRelevanceGateTest < ActiveSupport::TestCase
  def hit(score, citation)
    KnowledgeRerankedRetrieval::Result.new(article_key: 'TEST', citation: citation,
      rerank_score: score, cosine_distance: 0.2, content: 'synthetic', sha256: '0' * 64)
  end

  test 'pinned pilot policy loads and exposes its empirical cutoff' do
    gate = KnowledgeRelevanceGate.pilot
    assert_in_delta 7.421875, gate.threshold, 0.000001
    assert gate.threshold > 4.125
  end

  test 'abstain on weak candidates, preserve order and citations of qualified hits' do
    gate = KnowledgeRelevanceGate.pilot
    a = hit(9.1, 'TF-KB-012@vi:v2#chunk-0')
    b = hit(7.5, 'TF-KB-012@vi:v2#chunk-1')
    weak = hit(4.125, 'NM-KB-020@vi:v2#chunk-5')
    assert_equal [a, b], gate.filter([a, weak, b])
    assert_empty gate.filter([weak])
  end

  test 'logit is not interpreted as a probability, a conservative cutoff can reject positives' do
    gate = KnowledgeRelevanceGate.pilot
    assert_empty gate.filter([hit(6.75, 'NM-KB-029@vi:v2#chunk-2')])
    assert_equal 1, gate.filter([hit(8.8984375, 'TF-KB-012@vi:v2#chunk-5')]).size
  end

  test 'DB changed since calibration makes policy fail closed before GPU use' do
    gate = KnowledgeRelevanceGate.pilot
    # Test DB intentionally does not contain the immutable 12/84 pilot corpus.
    assert_raises(IOError) { gate.validate! }
  end
end
