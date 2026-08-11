Rails.application.routes.draw do
  resource :session
  resource :registration, only: %i[ new create ]
  resources :passwords, param: :token

  resources :projects, only: %i[ index show create update ] do
    member do
      patch :complete
      patch :drop
      patch :reopen
    end
  end

  resources :tasks, only: %i[ create update ] do
    member do
      patch :move_to_open
      patch :complete
      patch :drop
      patch :reopen
    end
  end
  get "inbox", to: "tasks#inbox", as: :inbox

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "tasks#index"
end
