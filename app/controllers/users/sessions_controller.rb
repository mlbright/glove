module Users
  class SessionsController < Devise::SessionsController
    skip_before_action :authenticate_user!, only: %i[new]

    def new
      if user_signed_in?
        redirect_to dashboard_path
      else
        render :new
      end
    end

    def destroy
      super
    end
  end
end
