Rails.application.routes.draw do
  root 'dashboard#index'
  get '/healthz', to: 'health#show', as: :health
  get '/demo/sign_in', to: 'demo_sessions#new', as: :demo_sign_in
  post '/demo/sign_in', to: 'demo_sessions#create'
  delete '/demo/sign_out', to: 'demo_sessions#destroy', as: :demo_sign_out
  resources :tickets, only: %i[index new create show] do
    resources :ticket_messages, only: :create
    patch :status, on: :member, to: 'tickets#update_status', as: :status
  end
  resources :customers, only: %i[index show]
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
