Rails.application.routes.draw do
  root 'dashboard#index'
  get '/healthz', to: 'health#show', as: :health
  get '/demo/sign_in', to: 'demo_sessions#new', as: :demo_sign_in
  post '/demo/sign_in', to: 'demo_sessions#create'
  delete '/demo/sign_out', to: 'demo_sessions#destroy', as: :demo_sign_out
  get '/auth/sign_in', to: 'password_sessions#new', as: :password_sign_in
  post '/auth/sign_in', to: 'password_sessions#create'
  delete '/auth/sign_out', to: 'password_sessions#destroy', as: :password_sign_out
  get '/platform', to: 'platform_dashboard#index', as: :platform_dashboard
  get '/platform/sign_in', to: 'platform_sessions#new', as: :platform_sign_in
  post '/platform/sign_in', to: 'platform_sessions#create'
  delete '/platform/sign_out', to: 'platform_sessions#destroy', as: :platform_sign_out
  get '/platform/organizations', to: 'platform_organizations#index', as: :platform_organizations
  get '/platform/organizations/new', to: 'platform_organizations#new', as: :new_platform_organization
  post '/platform/organizations', to: 'platform_organizations#create'
  get '/platform/organizations/:id', to: 'platform_organizations#show', as: :platform_organization
  patch '/platform/organizations/:id', to: 'platform_organizations#update'
  patch '/platform/organizations/:id/lifecycle', to: 'platform_organizations#lifecycle', as: :lifecycle_platform_organization
  post '/platform/organizations/:organization_id/owners', to: 'platform_owners#create', as: :platform_organization_owners
  patch '/platform/organizations/:organization_id/owners/:id', to: 'platform_owners#update', as: :platform_organization_owner
  get '/platform/audit', to: 'platform_audit_events#index', as: :platform_audit_events
  get '/settings', to: 'organization_settings#show', as: :organization_settings
  patch '/settings', to: 'organization_settings#update'
  resources :tickets, only: %i[index new create show] do
    resources :ticket_messages, only: :create
    patch :status, on: :member, to: 'tickets#update_status', as: :status
    patch :assign, on: :member, to: 'tickets#assign', as: :assign
  end
  resources :staff_members, only: %i[index create update]
  resources :customers, only: %i[index show new create edit update] do
    patch :archive, on: :member
  end
  resources :knowledge_articles, only: %i[index show] do
    post :approve, on: :member
    get :compare, on: :member
  end
  get '/kb/ai-search', to: 'knowledge_ai_search#show', as: :kb_ai_search
  post '/kb/ai-search', to: 'knowledge_ai_search#search'
  get '/kb/ai-search/runs/:id', to: 'knowledge_ai_search#run_status', as: :kb_ai_search_run
  get '/records/teamflow/invoice', to: 'business_records#teamflow_invoice', as: :teamflow_invoice
  get '/records/novamart/order', to: 'business_records#novamart_order', as: :novamart_order
end
