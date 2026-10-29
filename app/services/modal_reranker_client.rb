# frozen_string_literal: true
require 'net/http'
require 'json'
require 'digest'
require 'uri'

# Real cross-encoder scores from the pinned Qwen3-Reranker-4B Modal service.
# Caller MUST pass only tenant/ACL-approved KB candidates and a privacy-reviewed query.
class ModalRerankerClient
  MODEL_ID = 'Qwen/Qwen3-Reranker-4B'
  MODEL_REVISION = '22e683669bc0f0bd69640a1354a6d0aebcfeede5'
  MAX_DOCUMENTS = 12

  attr_reader :model_id, :model_revision

  def initialize(url: ENV['MODAL_RERANK_URL'], token: ENV['MODAL_RERANK_TOKEN'],
                 proxy_key: ENV['MODAL_PROXY_KEY'], proxy_secret: ENV['MODAL_PROXY_SECRET'])
    @uri = URI.parse(url.to_s)
    raise ArgumentError, 'HTTPS Modal reranker URL required' unless
      @uri.is_a?(URI::HTTPS) && @uri.host.to_s.end_with?('.modal.run') &&
      @uri.path.end_with?('/rerank')
    raise ArgumentError, 'reranker token missing' if token.to_s.length < 20
    raise ArgumentError, 'Modal proxy credentials required' unless proxy_key.to_s.match?(/\Awk-[A-Za-z0-9_-]+\z/) && proxy_secret.to_s.match?(/\Aws-[A-Za-z0-9_-]+\z/)
    @proxy_key, @proxy_secret = proxy_key, proxy_secret
    @token = token
    @model_id = MODEL_ID
    @model_revision = MODEL_REVISION
  end

  def score(query:, documents:)
    raise ArgumentError, 'invalid query' unless query.is_a?(String) &&
      !query.strip.empty? && query.bytesize <= 4_096 && query.valid_encoding?
    raise ArgumentError, 'invalid documents' unless documents.is_a?(Array) &&
      documents.size.between?(1, MAX_DOCUMENTS) &&
      documents.all? { |doc| doc.is_a?(String) && doc.valid_encoding? &&
        !doc.strip.empty? && doc.bytesize <= 16_384 }

    connection = Net::HTTP.new(@uri.host, @uri.port)
    connection.use_ssl = true
    connection.open_timeout = 8
    connection.read_timeout = 360
    req = Net::HTTP::Post.new(@uri.request_uri)
    req['Authorization'] = "Bearer #{@token}"
    req['Modal-Key'] = @proxy_key
    req['Modal-Secret'] = @proxy_secret
    req['Content-Type'] = 'application/json'
    req.body = JSON.generate(query: query, documents: documents)
    response = connection.request(req)
    raise IOError, "Modal reranker HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    payload = JSON.parse(response.body)
    expected_documents = documents.map { |d| Digest::SHA256.hexdigest(d) }
    raise IOError, 'rerank provenance mismatch' unless
      payload['model_id'] == MODEL_ID && payload['model_revision'] == MODEL_REVISION &&
      payload['score_type'] == 'raw_logit' &&
      payload['query_sha256'] == Digest::SHA256.hexdigest(query) &&
      payload['document_sha256'] == expected_documents
    scores = payload['scores']
    raise IOError, 'rerank score mismatch' unless scores.is_a?(Array) &&
      scores.size == documents.size && scores.all? { |v| v.is_a?(Numeric) && v.finite? }
    scores
  rescue JSON::ParserError
    raise IOError, 'invalid reranker JSON response'
  end
end
