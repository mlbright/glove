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

      sign_in_and_redirect @user, event: :authentication
      set_flash_message(:notice, :success, kind: kind) if is_navigational_format?
    rescue User::EmailNotAllowed => e
      Rails.logger.warn("Rejected sign-in for #{e.email}: not on ALLOWED_EMAILS")
      redirect_to new_user_session_path,
                  alert: "This app is private. #{e.email} is not authorized."
    rescue User::EmailMissing
      Rails.logger.warn("Rejected sign-in: provider returned no verified email")
      redirect_to new_user_session_path,
                  alert: "#{kind} did not provide an email address."
    rescue StandardError => e
      Rails.logger.error("OmniAuth failure: #{e.class}: #{e.message}")
      redirect_to new_user_session_path, alert: "Authentication failed."
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
