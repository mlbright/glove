class Transaction < ApplicationRecord
  include Revisable

  ENTRY_TYPES = { income: 0, expense: 1 }.freeze

  # The label an adjustment carries. A gap closed on someone's instruction is an
  # ordinary visible row, and says so. See docs/adr/0002.
  ADJUSTMENT_DESCRIPTION = "Balance adjustment"

  belongs_to :account
  belongs_to :csv_import, optional: true
  belongs_to :adjusted_checkpoint,
             class_name: "Checkpoint",
             foreign_key: :adjusts_checkpoint_id,
             optional: true,
             inverse_of: :adjustments

  has_many :transaction_tags, dependent: :destroy, foreign_key: :transaction_id, inverse_of: :transaction_record
  has_many :tags, through: :transaction_tags

  monetize :amount_cents

  enum :entry_type, ENTRY_TYPES
  enum :status, { pending: 0, cleared: 1, canceled: 2 }

  validates :amount_cents, numericality: { greater_than: 0 }
  validates :entry_type, :occurred_on, presence: true

  scope :for_month, ->(datetime) { where(occurred_on: datetime.beginning_of_month..datetime.end_of_month) }
  scope :income, -> { where(entry_type: ENTRY_TYPES[:income]) }
  scope :expenses, -> { where(entry_type: ENTRY_TYPES[:expense]) }

  scope :counting_toward_balance, -> { where(excludes_from_balance: false) }

  # A checkpoint accounts for everything on or before its own day, so only what
  # follows it contributes to the balance. Composing the two scopes bounds an
  # interval: after one checkpoint and through the next.
  scope :after_checkpoint, ->(checkpoint) { where(occurred_on: checkpoint.closes_before..) }
  scope :through_checkpoint, ->(checkpoint) { where(occurred_on: ...checkpoint.closes_before) }

  # Income adds, everything else subtracts. The one place that sign convention
  # is written down, so a balance and a reconciliation cannot disagree about it.
  def self.signed_cents
    sql = ActiveRecord::Base.sanitize_sql_array([
      "CASE WHEN entry_type = ? THEN amount_cents ELSE -amount_cents END",
      entry_types[:income]
    ])
    sum(Arel.sql(sql))
  end

  def amount_signed
    income? ? amount : -amount
  end

  def adjustment? = adjusts_checkpoint_id.present?

  def imported? = csv_import_id.present?
end
