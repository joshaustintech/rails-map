Rails.application.routes.draw do
  resources :users, only: [:show, :update]
  get "/health", to: "health#show"
  get "/admin/users/:id", to: "admin/users#show"
  get "health", to: "health#show"
  if Rails.env.production?
    get "/conditional", to: "conditional#show"
  end
  draw :tenant_routes
end
