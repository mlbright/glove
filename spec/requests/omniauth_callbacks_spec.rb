require "rails_helper"

RSpec.describe "OmniAuth callbacks", type: :request do
  def mock_google_auth(email:, uid: "123")
    info = { name: "Person" }
    info[:email] = email unless email.nil?

    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: uid, info: info
    )
  end

  def sign_in_with_google
    post user_google_oauth2_omniauth_authorize_path
    follow_redirect!
  end

  around do |example|
    original_env = ENV["ALLOWED_EMAILS"]
    original_test_mode = OmniAuth.config.test_mode
    ENV["ALLOWED_EMAILS"] = "person@example.com"
    OmniAuth.config.test_mode = true

    example.run

    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = original_test_mode
    ENV["ALLOWED_EMAILS"] = original_env
  end

  it "signs in an allowlisted address" do
    mock_google_auth(email: "person@example.com")

    sign_in_with_google

    expect(response).to redirect_to(dashboard_path)
    expect(User.count).to eq(1)
  end

  it "rejects an address that is not allowlisted, naming it" do
    mock_google_auth(email: "stranger@example.com")

    sign_in_with_google

    expect(response).to redirect_to(new_user_session_path)
    expect(flash[:alert]).to eq("This app is private. stranger@example.com is not authorized.")
    expect(User.count).to be_zero
  end

  it "rejects a sign-in with no verified email" do
    mock_google_auth(email: nil)

    sign_in_with_google

    expect(response).to redirect_to(new_user_session_path)
    expect(flash[:alert]).to eq("Google did not provide an email address.")
    expect(User.count).to be_zero
  end

  it "denies an otherwise-valid address when ALLOWED_EMAILS is unset" do
    ENV["ALLOWED_EMAILS"] = nil
    mock_google_auth(email: "person@example.com")

    sign_in_with_google

    expect(response).to redirect_to(new_user_session_path)
    expect(User.count).to be_zero
  end

  it "locks out an existing user once removed from the allowlist" do
    user = create(:user, email: "person@example.com", uid: "123")
    ENV["ALLOWED_EMAILS"] = "someone-else@example.com"
    mock_google_auth(email: "person@example.com")

    sign_in_with_google

    expect(response).to redirect_to(new_user_session_path)
    expect(user.reload).to be_persisted
  end
end
