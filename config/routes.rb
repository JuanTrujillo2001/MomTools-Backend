Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  post "login", to: "sessions#create"

  get "me", to: "me#show"

  resources :catalog_types, only: [:index]

  resources :suppliers, only: [:index, :show, :create, :update, :destroy]

  resources :catalogs, only: [:index, :show, :create, :update, :destroy] do
    resources :sheet_configs, only: [:index, :create, :update, :destroy]
  end

  resources :cart_items, only: [:index, :create, :update, :destroy]

  get "cart_items/export", to: "cart_items#export"

  get "search", to: "search#index"
  get "search/export", to: "search#export"

  # Defines the root path route ("/")
  # root "posts#index"
end
