require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  let(:user) { create(:user) }

  it "requires authentication" do
    get dashboard_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "renders metrics when signed in" do
    sign_in user
    get dashboard_path
    expect(response).to have_http_status(:ok)
  end
end
