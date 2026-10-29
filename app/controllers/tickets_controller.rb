class TicketsController < ApplicationController
  before_action :require_writer, only: %i[new create update_status]

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
    @tickets = scoped_tickets.includes(:customer).order(created_at: :desc).limit(200)
    @tickets = @tickets.where(status: @status) if @status
  end

  def new
    @customers = Customer.where(organization_id: current_organization.id).order(:external_key)
    @categories = CATEGORIES.fetch(current_organization.vertical)
    @ticket = Ticket.new(priority: 'P3', status: 'new')
  end

  def create
    customer = Customer.where(organization_id: current_organization.id).find(params.require(:customer_id))
    category = params.require(:category).to_s
    priority = params.require(:priority).to_s
    body = params.require(:initial_message).to_s.strip
    unless CATEGORIES.fetch(current_organization.vertical).include?(category) && %w[P1 P2 P3 P4].include?(priority) && body.present? && body.length <= 10_000
      redirect_to new_ticket_path, alert: t('tickets.invalid_input')
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
    redirect_to ticket_path(@ticket), notice: t('tickets.created')
  end

  def show
    @ticket = scoped_tickets.includes(:customer).find(params[:id])
    @messages = TicketMessage.where(organization_id: current_organization.id, ticket_id: @ticket.id).order(:created_at)
    @idempotency_key = SecureRandom.uuid
  end

  def update_status
    ticket = scoped_tickets.find(params[:id])
    desired = params.require(:status).to_s
    unless TRANSITIONS.fetch(ticket.status).include?(desired)
      redirect_to ticket_path(ticket), alert: t('tickets.invalid_transition')
      return
    end
    ActiveRecord::Base.transaction do
      ticket.lock!
      raise ActiveRecord::RecordInvalid, ticket unless TRANSITIONS.fetch(ticket.status).include?(desired)
      old = ticket.status
      ticket.update!(status: desired)
      audit!(action: 'ticket.status_changed', ticket: ticket, metadata: {from: old, to: desired})
    end
    redirect_to ticket_path(ticket), notice: t('tickets.updated')
  end
end
