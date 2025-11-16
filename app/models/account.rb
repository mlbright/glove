class Account < ApplicationRecord
  belongs_to :user

  has_many :transactions, dependent: :destroy
  has_many :schedules, dependent: :nullify

  enum :account_type, { checking: 0, savings: 1, credit_card: 2, cash: 3, investment: 4 }, default: :checking

  validates :name, presence: true, uniqueness: { scope: :user_id }

  scope :active, -> { where(archived_at: nil) }

  def balance
    income_value = Transaction.entry_types[:income]
    transactions.sum("CASE WHEN entry_type = #{income_value} THEN amount ELSE -amount END")
  end
end
