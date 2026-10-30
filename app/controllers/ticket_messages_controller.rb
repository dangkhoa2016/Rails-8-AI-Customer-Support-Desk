class TicketMessagesController < ApplicationController
  before_action :require_writer

  def create
    ticket = scoped_tickets.find(params[:ticket_id])
    body = params.require(:body).to_s.strip
    visibility = params.require(:visibility).to_s
    key = params.require(:idempotency_key).to_s
    unless %w[public internal].include?(visibility) && body.present? && body.length <= 10_000 && key.match?(/\A[0-9a-f-]{36}\z/)
      redirect_to ticket_path(ticket), alert: t('tickets.invalid_input'), status: :see_other
      return
    end
    if visibility == 'public' && params[:review_confirmed] != '1'
      redirect_to ticket_path(ticket), alert: t('tickets.approval_required'), status: :see_other
      return
    end
    ActiveRecord::Base.transaction do
      existing = TicketMessage.find_by(organization_id: current_organization.id, idempotency_key: key)
      if existing
        raise ActiveRecord::RecordNotFound unless existing.ticket_id == ticket.id
      else
        message = TicketMessage.create!(organization_id: current_organization.id,
          ticket_id: ticket.id, actor_type: 'agent', actor_user_id: current_user.id,
          visibility: visibility, channel: 'portal', body: body, idempotency_key: key,
          sent_at: Time.current)
        audit!(action: visibility == 'public' ? 'ticket.public_reply_approved' : 'ticket.internal_note_added',
          ticket: ticket, metadata: {message_id: message.id, review_confirmed: visibility == 'public'})
      end
    end
    respond_success(ticket)
  rescue ActiveRecord::RecordNotUnique
    respond_success(ticket)
  end

  private

  def respond_success(ticket)
    respond_to do |format|
      format.html { redirect_to ticket_path(ticket), notice: t('tickets.reply_saved'), status: :see_other }
      format.turbo_stream do
        messages = TicketMessage.where(organization_id: current_organization.id, ticket_id: ticket.id).order(:created_at)
        render turbo_stream: [
          turbo_stream.replace('ticket_conversation', partial: 'tickets/conversation', locals: {messages: messages}),
          turbo_stream.replace('ticket_reply_form', partial: 'tickets/reply_form', locals: {ticket: ticket}),
          turbo_stream.update('flash_messages', helpers.content_tag(:div, t('tickets.reply_saved'), class: 'notice', role: 'status'))
        ]
      end
    end
  end
end
