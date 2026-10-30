class TicketsController < ApplicationController
  before_action :require_writer, only: %i[new create update_status]
  before_action -> { require_permission(:ticket_assign) }, only: :assign

  CATEGORIES = {
    'b2b_saas' => %w[authentication billing_subscription permissions_workspace integrations_api exports_jobs incidents_bugs general_howto],
    'ecommerce' => %w[order_status shipping_exceptions returns_refunds missing_wrong_damaged product_warranty payment_issues]
  }.freeze

  TRANSITIONS = {
    'new' => %w[open pending_customer pending_internal resolved],
    'open' => %w[pending_customer pending_internal resolved],
    'pending_customer' => %w[open pending_internal resolved],
    'pending_internal' => %w[open pending_customer resolved],
    'resolved' => %w[open closed],
    'closed' => []
  }.freeze

  def index
    @status = params[:status].presence_in(TRANSITIONS.keys)
    @locale_filter = params[:customer_locale].presence_in(%w[vi en])
    @category_filter = params[:category].presence_in(CATEGORIES.fetch(current_organization.vertical))
    @query = params[:q].to_s.strip[0, 80]
    @assignee_filter = params[:assignee_user_id].to_s
    @available_assignees = Membership.includes(:user)
      .where(organization_id: current_organization.id, active: true, role: %w[owner admin agent])
      .order(:role, :id).to_a
    @total_tickets = scoped_tickets.count
    relation = scoped_tickets.joins(:customer).includes(:customer)
    relation = relation.where(status: @status) if @status
    relation = relation.where(customers: {locale: @locale_filter}) if @locale_filter
    relation = relation.where(category: @category_filter) if @category_filter
    if @assignee_filter == 'unassigned'
      relation = relation.where(assignee_id: nil)
    elsif @assignee_filter == 'me'
      relation = relation.where(assignee_id: current_user.id)
    elsif @assignee_filter.present?
      permitted = @available_assignees.any? { |member| member.user_id.to_s == @assignee_filter }
      relation = permitted ? relation.where(assignee_id: @assignee_filter.to_i) : relation.none
    end
    if @query.present?
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
      relation = relation.where('tickets.number ILIKE :q OR tickets.business_ref ILIKE :q OR customers.external_key ILIKE :q', q: pattern)
    end
    @filtered_count = relation.count
    @tickets = relation.order(created_at: :desc).limit(200)
  end

  def new
    @customers = Customer.where(organization_id: current_organization.id).active.order(:external_key)
    @categories = CATEGORIES.fetch(current_organization.vertical)
    @ticket = Ticket.new(priority: 'P3', status: 'new')
  end

  def create
    customer = Customer.where(organization_id: current_organization.id).active.find(params.require(:customer_id))
    category = params.require(:category).to_s
    priority = params.require(:priority).to_s
    body = params.require(:initial_message).to_s.strip
    unless CATEGORIES.fetch(current_organization.vertical).include?(category) && %w[P1 P2 P3 P4].include?(priority) && body.present? && body.length <= 10_000
      redirect_to new_ticket_path, alert: t('tickets.invalid_input'), status: :see_other
      return
    end
    @ticket = nil
    ActiveRecord::Base.transaction do
      # Serialize per-tenant sequential ticket numbering under the organization row lock.
      current_organization.lock!
      next_number = scoped_tickets.maximum(:id).to_i + 1
      prefix = current_organization.vertical == 'b2b_saas' ? 'TF' : 'NM'
      number = format('%s-TICKET-%06d', prefix, next_number)
      @ticket = scoped_tickets.create!(customer_id: customer.id, number: number,
        category: category, priority: priority, status: 'new', assignee_id: current_user.id)
      TicketMessage.create!(organization_id: current_organization.id, ticket_id: @ticket.id,
        actor_type: 'customer', visibility: 'public', channel: 'manual_intake',
        body: body, sent_at: Time.current)
      audit!(action: 'ticket.created', ticket: @ticket, metadata: {category: category, priority: priority})
    end
    redirect_to ticket_path(@ticket), notice: t('tickets.created'), status: :see_other
  end

  def show
    @ticket = scoped_tickets.includes(:customer).find(params[:id])
    messages = TicketMessage.where(organization_id: current_organization.id, ticket_id: @ticket.id)
    @messages = access_policy.visible_messages(messages).order(:created_at)
    @idempotency_key = SecureRandom.uuid
    @available_assignees = Membership.includes(:user)
      .where(organization_id: current_organization.id, active: true, role: %w[owner admin agent])
      .order(:role, :id).to_a if can?(:ticket_assign)
  end

  def assign
    ticket = scoped_tickets.find(params[:id])
    raw_user_id = params[:assignee_user_id].to_s
    return head :unprocessable_entity unless raw_user_id.blank? || raw_user_id.match?(/\A[1-9]\d{0,18}\z/)
    assignee = if raw_user_id.present?
      Membership.find_by(organization_id: current_organization.id,
        user_id: raw_user_id.to_i, active: true, role: %w[owner admin agent])
    end
    return head :unprocessable_entity if raw_user_id.present? && assignee.nil?

    ActiveRecord::Base.transaction do
      ticket.lock!
      if ticket.assignee_id != assignee&.user_id
        old = ticket.assignee_id
        ticket.update!(assignee_id: assignee&.user_id)
        audit!(action: 'ticket.assignee_changed', ticket: ticket,
          metadata: {from_user_id: old, to_user_id: assignee&.user_id})
      end
    end
    redirect_to ticket_path(ticket), notice: t('tickets.assignee_updated'), status: :see_other
  end

  def update_status
    ticket = scoped_tickets.find(params[:id])
    desired = params.require(:status).to_s
    unless TRANSITIONS.fetch(ticket.status).include?(desired)
      redirect_to ticket_path(ticket), alert: t('tickets.invalid_transition'), status: :see_other
      return
    end
    ActiveRecord::Base.transaction do
      ticket.lock!
      raise ActiveRecord::RecordInvalid, ticket unless TRANSITIONS.fetch(ticket.status).include?(desired)
      old = ticket.status
      ticket.update!(status: desired)
      audit!(action: 'ticket.status_changed', ticket: ticket, metadata: {from: old, to: desired})
    end
    respond_to do |format|
      format.html { redirect_to ticket_path(ticket), notice: t('tickets.updated'), status: :see_other }
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace('ticket_summary', partial: 'tickets/summary', locals: {ticket: ticket}),
          turbo_stream.replace('ticket_status_controls', partial: 'tickets/status_controls', locals: {ticket: ticket}),
          turbo_stream.update('flash_messages', helpers.content_tag(:div, t('tickets.updated'), class: 'notice', role: 'status'))
        ]
      end
    end
  end
end
