# frozen_string_literal: true
require 'net/http'
require 'json'
require 'digest'
require 'uri'

# Explicit, authenticated outbound service. Never transmit credentials to logs.
# NO live calls without configured endpoint AND operator opt-in.
class ModalEmbeddingClient
  MAX_TEXTS = 8
  DIMENSIONS = 2560
  MODEL_ID = 'Qwen/Qwen3-Embedding-4B'
  MODEL_REVISION = '5cf2132abc99cad020ac570b19d031efec650f2b'

  def initialize(url: ENV['MODAL_EMBEDDING_URL'], token: ENV['MODAL_EMBEDDING_TOKEN'],
                 model_id: MODEL_ID,
                 model_revision: MODEL_REVISION,
                 proxy_key: ENV['MODAL_PROXY_KEY'], proxy_secret: ENV['MODAL_PROXY_SECRET'])
    @uri = URI.parse(url.to_s)
    raise ArgumentError, 'HTTPS Modal URL required' unless @uri.is_a?(URI::HTTPS) &&
      @uri.host.to_s.end_with?('.modal.run') && @uri.path.end_with?('/embed')
    raise ArgumentError, 'embedding token required' if token.to_s.length < 20
    raise ArgumentError, 'unexpected model ID' unless model_id == MODEL_ID
    raise ArgumentError, 'unexpected model revision' unless model_revision == MODEL_REVISION
    raise ArgumentError, 'pinned model revision required' unless model_revision.to_s.match?(/\A[a-zA-Z0-9_.-]{7,128}\z/)
    raise ArgumentError, 'Modal proxy credentials required' unless proxy_key.to_s.match?(/\Awk-[A-Za-z0-9_-]+\z/) && proxy_secret.to_s.match?(/\Aws-[A-Za-z0-9_-]+\z/)
    @proxy_key, @proxy_secret = proxy_key, proxy_secret
    @token = token
    @model_id = model_id
    @model_revision = model_revision
  end

  attr_reader :model_id, :model_revision

  def embed_documents(texts)
    embed(texts, 'document')
  end

  def embed_query(text)
    embed([text], 'query').first
  end

  private

  def embed(texts, kind)
    raise ArgumentError, 'invalid batch' unless texts.is_a?(Array) &&
      texts.length.between?(1, MAX_TEXTS) && texts.all? { |x| x.is_a?(String) && x.valid_encoding? &&
        !x.strip.empty? && x.bytesize <= 16_384 }
    request_body = JSON.generate({ texts: texts, kind: kind })
    http = Net::HTTP.new(@uri.host, @uri.port)
    http.use_ssl = true
    http.open_timeout = 8
    http.read_timeout = 360
    request = Net::HTTP::Post.new(@uri.request_uri)
    request['Authorization'] = "Bearer #{@token}"
    request['Modal-Key'] = @proxy_key
    request['Modal-Secret'] = @proxy_secret
    request['Content-Type'] = 'application/json'
    request.body = request_body
    response = http.request(request)
    raise IOError, "Modal embedding HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    payload = JSON.parse(response.body)
    expected_hashes = texts.map { |t| Digest::SHA256.hexdigest(t) }
    unless payload['model_id'] == @model_id && payload['model_revision'] == @model_revision &&
        payload['kind'] == kind && payload['input_sha256'] == expected_hashes
      raise IOError, 'embedding model or input provenance mismatch'
    end
    vectors = payload['vectors']
    raise IOError, 'embedding batch count mismatch' unless vectors.is_a?(Array) && vectors.length == texts.length
    vectors.each do |v|
      raise IOError, 'invalid embedding vector' unless v.is_a?(Array) && v.length == DIMENSIONS &&
        v.all? { |n| n.is_a?(Numeric) && n.finite? } && v.any? { |n| n != 0 }
    end
    vectors
  rescue JSON::ParserError
    raise IOError, 'embedding endpoint returned invalid JSON'
  end
end
