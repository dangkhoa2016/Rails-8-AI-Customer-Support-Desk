# frozen_string_literal: true
require 'benchmark'
require 'net/http'
# Deliberately local, synthetic-only exploration UI. NOT production authentication.
# Browser->Rails never receives model credentials. Only approved tenant KB is returned.
class KnowledgeAISearchController < ApplicationController
  before_action :require_staff_member
  before_action :require_local_demo
  before_action :disable_caching

  def show
    @scope_probe_requested = ENV['M2_ANSWERABILITY_SCOPE_ENABLE'] == 'YES'
    @scope_probe_blocked = @scope_probe_requested && !KnowledgeScopePreviewGate.eligible?
    @scope_probe_enabled = @scope_probe_requested && !@scope_probe_blocked
    @ready = configured? && !@scope_probe_blocked
    @locale = I18n.locale.to_s
    @synthetic_only = true
    @validation_error = t('ai_search.scope_probe_blocked') if @scope_probe_blocked
    # Examples must never silently cross tenant boundaries. An unknown tenant gets
    # no canned question rather than examples from another organization.
    @examples = case current_organization.slug
    when 'teamflow-cloud' then t('ai_search.examples.teamflow_cloud')
    when 'novamart-store' then t('ai_search.examples.novamart_store')
    else []
    end
    @results = nil
    @query_text = ''
    @run = if params[:run].present? && ENV['M5_ASYNC_SEARCH_ENABLE'] == 'YES'
      load_run!(params[:run])
    end
  end

  def search
    show
    unless @ready
      render :show, status: :service_unavailable
      return
    end
    query = params[:query].to_s.strip
    unless params[:privacy_confirmed] == '1' && safe_synthetic_query?(query)
      @validation_error = t('ai_search.invalid_query')
      render :show, status: :unprocessable_entity
      return
    end
    # Small session-level budget, NOT a production distributed rate limiter.
    now = Time.current.to_i
    last_call = session[:kb_ai_last_call].to_i
    remaining = session[:kb_ai_calls].to_i
    if remaining >= 20 || (last_call.positive? && (now - last_call) < 8)
      @validation_error = t('ai_search.rate_limited')
      render :show, status: :too_many_requests
      return
    end
    session[:kb_ai_calls] = remaining + 1
    session[:kb_ai_last_call] = now
    @query_text = query
    if ENV['M5_ASYNC_SEARCH_ENABLE'] == 'YES'
      run = AISearchRun.create!(organization: current_organization,
        membership: current_membership, request_role: current_membership.role,
        locale: @locale, query_text: query, query_sha256: Digest::SHA256.hexdigest(query))
      begin
        KnowledgeAISearchJob.perform_later(run.id)
      rescue StandardError
        run.update!(status: 'failed', error_code: 'QUEUE_UNAVAILABLE', finished_at: Time.current)
      end
      redirect_to kb_ai_search_path(run: run.public_id, locale: @locale), status: :see_other
      return
    end
    @elapsed_ms = (Benchmark.realtime do
      @results = KnowledgeRerankedRetrieval.search(
        organization: current_organization, role: current_membership.role,
        query: query, locale: @locale, embedding_client: ModalEmbeddingClient.new,
        reranker_client: ModalRerankerClient.new, candidate_limit: 12, limit: 5,
        query_privacy_reviewed: true, relevance_gate: KnowledgeRelevanceGate.pilot,
        answerability_verifier: (@scope_probe_enabled ? KnowledgeAnswerabilityScopeVerifier.pilot : nil)
      )
    end * 1000).round
    render :show
  rescue ArgumentError, IOError, Net::ReadTimeout, Net::OpenTimeout, Timeout::Error => error
    Rails.logger.warn('Knowledge AI unavailable: ' + error.class.name)
    @validation_error = t('ai_search.unavailable')
    @results = nil
    render :show, status: :service_unavailable
  end

  def run_status
    @run = load_run!(params[:id])
    @locale = @run.locale
    @results = @run.safe_hits
    @elapsed_ms = @run.elapsed_ms
    if request.headers['Turbo-Frame'] == "ai_search_run_#{@run.public_id}"
      render partial: 'knowledge_ai_search/run_status', locals: {run: @run}, layout: false
    else
      redirect_to kb_ai_search_path(run: @run.public_id, locale: @run.locale), status: :see_other
    end
  end

  private

  def load_run!(public_id)
    run = AISearchRun.visible_to(current_membership).find_by!(public_id: public_id)
    raise ActiveRecord::RecordNotFound if run.expired?
    run
  end

  def require_staff_member
    require_permission(:ai_search)
  end

  def require_local_demo
    # Passwordless synthetic sign-in MUST NOT be exposed to the public Internet.
    head :forbidden unless (Rails.env.development? || Rails.env.test?)
  end

  def configured?
    return false unless ENV['M2_SEMANTIC_UI_ENABLE'] == 'YES'
    valid_tokens = %w[MODAL_EMBEDDING_URL MODAL_EMBEDDING_TOKEN MODAL_RERANK_URL MODAL_RERANK_TOKEN].all? do |name|
      ENV[name].to_s.length >= 20
    end
    valid_tokens && ENV['MODAL_PROXY_KEY'].to_s.match?(/\Awk-[A-Za-z0-9_-]+\z/) &&
      ENV['MODAL_PROXY_SECRET'].to_s.match?(/\Aws-[A-Za-z0-9_-]+\z/)

  end

  def disable_caching
    response.headers['Cache-Control'] = 'no-store, private'
    response.headers['Pragma'] = 'no-cache'
  end

  def safe_synthetic_query?(query)
    return false unless query.valid_encoding? && query.length.between?(12, 300)
    return false if query.match?(/https?:\/\/|www\.|[\w.+-]+@[\w.-]+\.[a-z]{2,}/i)
    return false if query.match?(/(?:\+?\d[\d\s().-]{7,}\d)/) # phone/card-like data
    return false if query.include?(10.chr) || query.include?(13.chr)
    true
  end
end
