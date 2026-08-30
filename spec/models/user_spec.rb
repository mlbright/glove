require "rails_helper"
require "omniauth"

RSpec.describe User, type: :model do
  def auth_hash(email:, uid: "123", name: "Person")
    info = { name: name }
    info[:email] = email unless email.nil?

    OmniAuth::AuthHash.new(provider: "google_oauth2", uid: uid, info: info)
  end

  around do |example|
    original = ENV["ALLOWED_EMAILS"]
    ENV["ALLOWED_EMAILS"] = "person@example.com, Other@Example.COM"
    example.run
    ENV["ALLOWED_EMAILS"] = original
  end

  describe ".from_omniauth" do
    it "creates a user for an allowlisted address" do
      user = described_class.from_omniauth(auth_hash(email: "person@example.com"))

      expect(user).to be_persisted
      expect(user.email).to eq("person@example.com")
    end

    it "updates the existing user on repeat sign-in" do
      described_class.from_omniauth(auth_hash(email: "person@example.com"))

      expect {
        user = described_class.from_omniauth(auth_hash(email: "person@example.com"))
        expect(user.sign_in_count).to eq(2)
      }.not_to change(described_class, :count)
    end

    it "matches the allowlist case-insensitively and ignores surrounding space" do
      user = described_class.from_omniauth(auth_hash(email: "  OTHER@example.com  "))

      expect(user.email).to eq("other@example.com")
    end

    it "rejects an address that is not allowlisted" do
      expect {
        described_class.from_omniauth(auth_hash(email: "stranger@example.com"))
      }.to raise_error(described_class::EmailNotAllowed) { |error|
        expect(error.email).to eq("stranger@example.com")
      }
    end

    it "creates no user record when the address is rejected" do
      expect {
        begin
          described_class.from_omniauth(auth_hash(email: "stranger@example.com"))
        rescue described_class::EmailNotAllowed
          nil
        end
      }.not_to change(described_class, :count)
    end

    it "rejects an unverified address, which the strategy prunes from info" do
      # omniauth-google-oauth2 omits info[:email] entirely unless Google
      # reports email_verified, even when raw_info carries an address.
      expect {
        described_class.from_omniauth(auth_hash(email: nil))
      }.to raise_error(described_class::EmailMissing)
    end

    it "denies every address when ALLOWED_EMAILS is unset" do
      ENV["ALLOWED_EMAILS"] = nil

      expect {
        described_class.from_omniauth(auth_hash(email: "person@example.com"))
      }.to raise_error(described_class::EmailNotAllowed)
    end

    it "denies every address when ALLOWED_EMAILS is empty" do
      ENV["ALLOWED_EMAILS"] = "  ,  "

      expect {
        described_class.from_omniauth(auth_hash(email: "person@example.com"))
      }.to raise_error(described_class::EmailNotAllowed)
    end
  end

  describe ".allowed_emails" do
    it "normalizes and drops blank entries" do
      ENV["ALLOWED_EMAILS"] = "One@Example.com, ,two@example.com,"

      expect(described_class.allowed_emails).to eq(%w[one@example.com two@example.com])
    end
  end
end
