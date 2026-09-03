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

    resources :accounts do
      # new/create hang off the account; edit/update/destroy address the
      # checkpoint directly.
      resources :checkpoints, shallow: true, only: %i[new create edit update destroy]
    end
    # Closing a gap is an explicit instruction, never a side effect of anything.
    resources :checkpoints, only: [] do
      resource :adjustment, only: :create, controller: "checkpoint_adjustments"
    end
    resources :transactions do
      collection do
        get :tag_cloud
      end
    end
    resources :tags, only: %i[index edit update destroy]
    resources :csv_imports, only: %i[new create]
  end

  root to: "landing#index"

  get "up" => "rails/health#show", as: :rails_health_check
end
