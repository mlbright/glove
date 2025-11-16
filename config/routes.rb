Rails.application.routes.draw do
  devise_for :users, skip: %i[registrations passwords], controllers: {
    omniauth_callbacks: "users/omniauth_callbacks",
    sessions: "users/sessions"
  }

  devise_scope :user do
    get "users/sign_in", to: "users/sessions#new", as: :new_user_session
    delete "users/sign_out", to: "users/sessions#destroy", as: :destroy_user_session
  end

  authenticate :user do
    root to: "dashboard#index", as: :authenticated_root
    get :dashboard, to: "dashboard#index"

    resources :accounts
    resources :transactions do
      collection do
        get :tag_cloud
      end
    end
    resources :schedules
    resources :tags, only: %i[index]
    resources :import_templates
    resources :import_batches do
      member do
        post :start
      end
    end
  end

  root to: "landing#index"

  get "up" => "rails/health#show", as: :rails_health_check
end
