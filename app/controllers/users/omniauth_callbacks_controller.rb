module Users
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    skip_before_action :authenticate_user!

    def google_oauth2
      handle_auth "Google"
    end

    def failure
      redirect_to root_path, alert: "Authentication failed: #{failure_message}"
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

    def failure_message
      exception = request.env["omniauth.error"]
      error_type = request.env["omniauth.error.type"]
      exception&.error_reason || error_type || "Unknown error"
    end

    def after_omniauth_failure_path_for(_scope)
      root_path
    end
  end
end
