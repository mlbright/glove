class User < ApplicationRecord
  devise :rememberable, :omniauthable, omniauth_providers: %i[google_oauth2 github]

  has_many :accounts, dependent: :destroy
  has_many :transactions, dependent: :destroy
  has_many :tags, dependent: :destroy
  has_many :schedules, dependent: :destroy
  has_many :import_templates, dependent: :destroy
  has_many :import_batches, dependent: :destroy

  validates :email, presence: true, uniqueness: true
  validates :provider, :uid, presence: true

  def self.from_omniauth(auth)
    info = auth.info || {}.with_indifferent_access
    user = find_or_initialize_by(provider: auth.provider, uid: auth.uid)
    user.email = info[:email].presence || auth.extra&.dig(:raw_info, :email) || "unknown@example.com"
    user.name = info[:name].presence || info[:nickname] || user.email
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
