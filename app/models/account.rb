class Account < ApplicationRecord
  has_many :transactions, dependent: :destroy

  validates :name, presence: true, uniqueness: true

  scope :active, -> { where(archived_at: nil) }

  def balance
    income_value = Transaction.entry_types[:income]
    sql = ActiveRecord::Base.sanitize_sql_array([
      "CASE WHEN entry_type = ? THEN amount_cents ELSE -amount_cents END",
      income_value
    ])
    cents = transactions.sum(Arel.sql(sql))
    Money.new(cents, :cad)
  end
end
