# M2 KB: tenant scoped; drafts are editorial-only, never returned by the retrieval service.
class KnowledgeArticlesController < ApplicationController
  before_action :load_article, only: %i[show compare approve]
  before_action :require_reviewer, only: %i[compare approve]

  def index
    @query = params[:q].to_s.strip.first(300)
    @search_results = KnowledgeRetrieval.search(organization: current_organization,
      role: current_membership.role, query: @query, locale: I18n.locale.to_s) if @query.present?
    @search_results ||= []
    base = KnowledgeArticle.where(organization_id: current_organization.id)
    base = base.where(audience: 'public') unless staff?
    versions = KnowledgeArticleVersion.where(organization_id: current_organization.id,
      locale: I18n.locale.to_s)
    unless reviewer?
      versions = versions.where(status: 'approved', policy_version: current_organization.policy_version)
        .where('knowledge_article_versions.approved_by IS NOT NULL AND knowledge_article_versions.approved_at IS NOT NULL')
        .where('knowledge_article_versions.effective_from <= ?', Date.current)
        .where('knowledge_article_versions.effective_to IS NULL OR knowledge_article_versions.effective_to >= ?', Date.current)
    end
    @versions = versions.where(knowledge_article_id: base.select(:id)).includes(:knowledge_article)
      .order('knowledge_article_id ASC, version_number DESC').to_a
    @versions = @versions.uniq(&:knowledge_article_id)
    @total_articles = base.count
    @published_count = KnowledgeArticleVersion.where(organization_id: current_organization.id,
      locale: I18n.locale.to_s, status: 'approved').count
    @priority_review_articles = []
    if reviewer?
      proposals = JSON.parse(File.read(Rails.root.join('review/m2_priority_editorial_proposals_20261029.json')))
      keys = proposals.fetch('revisions').map { |v| v.fetch('article_key') }.uniq
      @priority_review_articles = base.where(article_key: keys).order(:article_key).to_a
    end
  end

  def show
    @version = @article.knowledge_article_versions.where(organization_id: current_organization.id,
      locale: I18n.locale.to_s)
    unless reviewer?
      @version = @version.where(status: 'approved', policy_version: current_organization.policy_version)
        .where('approved_by IS NOT NULL AND approved_at IS NOT NULL')
        .where('effective_from <= ?', Date.current)
        .where('effective_to IS NULL OR effective_to >= ?', Date.current)
    end
    @version = @version.find(params[:version_id]) if params[:version_id].present?
    @version = @version.order(version_number: :desc).first unless @version.is_a?(KnowledgeArticleVersion)
    raise ActiveRecord::RecordNotFound unless @version
    raise ActiveRecord::RecordNotFound unless reviewer? || @version.active_on?
  end

  # Owner/admin-only side-by-side editorial view; never exposes drafts to agents/viewers.
  def compare
    @language_versions = {}
    %w[vi en].each do |lang|
      @language_versions[lang] = @article.knowledge_article_versions
        .where(organization_id: current_organization.id, locale: lang)
        .order(version_number: :desc).to_a
    end
    @canonical_policies = []
    @canonical_clarifications = []
    canonical = JSON.parse(File.read(Rails.root.join(
      'docs/RAILS8_AI_SUPPORT_DESK_CANONICAL_BLUEPRINT_2026-10-28.json')))
    org = canonical.fetch('organizations').find { |entry| entry.fetch('slug') == current_organization.slug }
    if org
      @canonical_policies = org.fetch('rules').select { |rule| @article.policy_refs.include?(rule.fetch('id')) }
      @canonical_clarifications = canonical.fetch('implementation_clarifications').select do |clar|
        (clar.fetch('policy_refs') & @article.policy_refs).any?
      end
    end
  end

  def approve
    version = @article.knowledge_article_versions.where(organization_id: current_organization.id).find(params.require(:version_id))
    KnowledgePublication.approve!(version: version, membership: current_membership,
      reviewer_notes: params[:reviewer_notes], review_attested: params[:review_attested] == '1')
    audit!(action: 'kb.version_approved', metadata: { article_key: @article.article_key,
      locale: version.locale, version: version.version_number, sha256: version.sha256,
      editorial_attested: true, reviewer_notes: params[:reviewer_notes].to_s.strip })
    destination = params[:review_compare] == '1' ? compare_knowledge_article_path(@article) : knowledge_article_path(@article, locale: version.locale)
    redirect_to destination, notice: t('knowledge.approved'), status: :see_other
  rescue ArgumentError => e
    destination = params[:review_compare] == '1' ? compare_knowledge_article_path(@article) : knowledge_article_path(@article)
    redirect_to destination, alert: e.message, status: :see_other
  end

  private

  def load_article
    @article = KnowledgeArticle.where(organization_id: current_organization.id).find(params[:id])
    raise ActiveRecord::RecordNotFound unless staff? || @article.audience == 'public'
  end

  def staff?
    %w[owner admin agent].include?(current_membership.role)
  end

  def reviewer?
    %w[owner admin].include?(current_membership.role)
  end

  def require_reviewer
    head :forbidden unless reviewer?
  end
end
