class HealthController < ActionController::API
  def show
    render json: { application: 'rails8-ai-customer-support-desk', stage: 'M1_RAILS_SCAFFOLD', status: 'ok', ai_inference: 'NOT_CONFIGURED' }
  end
end
