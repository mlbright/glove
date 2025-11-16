module Users
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    skip_before_action :authenticate_user!

    def google_oauth2
      handle_auth "Google"
    end

    def github
      handle_auth "GitHub"
    end

    private

    def handle_auth(kind)
      @user = User.from_omniauth(request.env["omniauth.auth"])

      if @user.persisted?
        sign_in_and_redirect @user, event: :authentication
        set_flash_message(:notice, :success, kind: kind) if is_navigational_format?
      else
        redirect_to root_path, alert: "Unable to sign in with #{kind}."
      end
    rescue StandardError => e
      Rails.logger.error("OmniAuth failure: #{e.message}")
      redirect_to root_path, alert: "Authentication failed."
    end
  end
end
