class User < ApplicationRecord
  # Raised when OmniAuth hands back an address that is not on the sign-in
  # allowlist. Carries the address so the callback controller can name it.
  class EmailNotAllowed < StandardError
    attr_reader :email

    def initialize(email)
      @email = email
      super("#{email.presence || 'blank address'} is not on the sign-in allowlist")
    end
  end

  # Raised when the provider returns no verified email address at all.
  class EmailMissing < StandardError; end

  devise :rememberable, :omniauthable, omniauth_providers: %i[google_oauth2]

  has_many :tags, dependent: :destroy

  validates :email, presence: true, uniqueness: true
  validates :provider, :uid, presence: true

  # Addresses permitted to sign in, from the ALLOWED_EMAILS environment
  # variable (comma-separated). Normalized for comparison.
  def self.allowed_emails
    ENV.fetch("ALLOWED_EMAILS", "").split(",").filter_map do |email|
      normalized = normalize_email(email)
      normalized.presence
    end
  end

  def self.email_allowed?(email)
    normalized = normalize_email(email)
    return false if normalized.blank?

    allowed = allowed_emails
    if allowed.empty?
      Rails.logger.error("ALLOWED_EMAILS is unset or empty; denying all sign-ins")
      return false
    end

    allowed.include?(normalized)
  end

  def self.normalize_email(email)
    email.to_s.strip.downcase
  end

  def self.from_omniauth(auth)
    info = auth.info || {}

    # omniauth-google-oauth2 sets info[:email] only when Google reports the
    # address as verified, and prunes the key otherwise. A blank value here
    # means unverified or absent - never fall back to raw_info[:email], which
    # is the unverified address the strategy deliberately withheld.
    email = normalize_email(info[:email])
    raise EmailMissing if email.blank?
    raise EmailNotAllowed, email unless email_allowed?(email)

    user = find_or_initialize_by(provider: auth.provider, uid: auth.uid)
    user.email = email
    user.name = info[:name].presence || info[:nickname] || email
    user.avatar_url = info[:image]
    user.last_sign_in_at = Time.current
    user.sign_in_count = user.sign_in_count.to_i + 1
    user.save!
    user
  end

  def display_name
    name.presence || email
  end
end
