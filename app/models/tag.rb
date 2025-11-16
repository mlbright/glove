class Tag < ApplicationRecord
  belongs_to :user

  has_many :transaction_tags, dependent: :destroy
  has_many :transactions, through: :transaction_tags

  validates :name, :slug, presence: true
  validates :slug, uniqueness: { scope: :user_id }

  before_validation :assign_slug

  private

  def assign_slug
    self.slug = name.to_s.parameterize if slug.blank? && name.present?
  end
end
