Rails.application.routes.draw do
  namespace :admin do
      resources :broadcast_point_groups
      resources :broadcast_point_group_memberships
      resources :locations
      resources :media_assets
      resources :media_plans do
        member do
          delete :cancel
          get :reschedule
          patch :reschedule
        end
      end
      resources :organizations
      resources :play_logs
      resources :rotations
      resources :rotation_items
      resources :screens
      resources :screen_tags
      resources :stations
      resources :tags
      resources :users

      root to: "media_plans#index"
    end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html
  # Cabinet (HTML), internal JSON, and Api::V1 device routes are added in later phases (see tasks.md).

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "media_assets#index"

  resources :media_assets, only: %i[index create update]

  resources :rotations do
    resources :rotation_items, only: %i[create destroy], path: "items"
  end

  resources :broadcast_point_groups do
    member do
      post :add_screens
      delete :remove_member
    end
  end

  resources :locations, only: %i[index edit update]

  resources :owned_screens

  resources :media_plans, except: %i[destroy] do
    member do
      delete :cancel
      get :reschedule
      patch :reschedule
    end
  end

  get "finance", to: "finance#show", as: :finance

  namespace :fleet do
    resources :screens, only: %i[index show]
  end

  namespace :internal do
    patch "rotations/:rotation_id/reorder", to: "rotations/reorders#update", as: :rotation_reorder
  end

  namespace :api do
    namespace :agent do
      namespace :v1 do
        get :package, to: "packages#show"
        get :config, to: "configs#show"
        post :play_events, to: "play_events#create"
      end
    end
  end

  get "login", to: "sessions#new", as: :login
  post "login", to: "sessions#create"
  delete "logout", to: "sessions#destroy", as: :logout

  resource :locale, only: :update
end
