class Account < ApplicationRecord
  has_many :transactions, dependent: :destroy

  # An account has exactly one import format, or none. The format is a property
  # of the account rather than a choice made at import time, so that picking an
  # account settles which parser its CSV gets. See docs/adr/0001.
  enum :import_format, CsvImports::Format.enum_mapping, validate: { allow_nil: true }

  validates :name, presence: true, uniqueness: true

  scope :active, -> { where(archived_at: nil) }

  # Only accounts with a format can receive a CSV import: without one there is
  # no way to know how to read the file.
  def importable? = import_format.present?

  def import_format_label = CsvImports::Format.label_for(import_format)

  def balance
    income_value = Transaction.entry_types[:income]
    sql = ActiveRecord::Base.sanitize_sql_array([
      "CASE WHEN entry_type = ? THEN amount_cents ELSE -amount_cents END",
      income_value
    ])
    cents = transactions.where(excludes_from_balance: false).sum(Arel.sql(sql))
    Money.new(cents, :cad)
  end
end
