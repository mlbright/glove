require "rails_helper"
require "omniauth"

RSpec.describe User, type: :model do
  it "creates or updates from omniauth" do
    auth_hash = OmniAuth::AuthHash.new(
      provider: "github",
      uid: "123",
      info: { email: "person@example.com", name: "Person" }
    )

    user = described_class.from_omniauth(auth_hash)
    expect(user).to be_persisted
    expect(user.email).to eq("person@example.com")
  end
end
