Rails.application.routes.draw do
  mount_avo
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

  resources :playlists do
    resources :playlist_items, only: %i[create destroy], path: "items"
  end

  resources :broadcast_points, except: :destroy

  resources :point_groups do
    member do
      post :add_points
      delete :remove_member
    end
  end

  resources :schedule_rules

  namespace :internal do
    patch "playlists/:playlist_id/reorder", to: "playlists/reorders#update", as: :playlist_reorder
  end

  get "login", to: "sessions#new", as: :login
  post "login", to: "sessions#create"
  delete "logout", to: "sessions#destroy", as: :logout
end
