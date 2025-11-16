class Transaction < ApplicationRecord
  ENTRY_TYPES = { income: 0, expense: 1 }.freeze

  attr_accessor :acted_by

  belongs_to :user
  belongs_to :account
  belongs_to :schedule, optional: true
  belongs_to :import_batch, optional: true

  has_many :transaction_tags, dependent: :destroy, foreign_key: :transaction_id, inverse_of: :transaction_record
  has_many :tags, through: :transaction_tags
  has_many :transaction_revisions, dependent: :destroy, foreign_key: :transaction_id, inverse_of: :transaction_record

  enum :entry_type, ENTRY_TYPES
  enum :status, { pending: 0, cleared: 1, canceled: 2 }

  validates :amount, numericality: { greater_than: 0 }
  validates :entry_type, :occurred_on, presence: true

  scope :for_month, ->(date) { where(occurred_on: date.beginning_of_month..date.end_of_month) }
  scope :income, -> { where(entry_type: ENTRY_TYPES[:income]) }
  scope :expenses, -> { where(entry_type: ENTRY_TYPES[:expense]) }

  after_create_commit -> { record_revision("create") }
  after_update_commit -> { record_revision("update") }
  after_destroy_commit -> { record_revision("destroy") }

  def amount_signed
    income? ? amount : -amount
  end

  private

  def record_revision(action)
    TransactionRevision.create!(
      transaction_record: self,
      user: acted_by || user,
      action: action,
      change_log: change_log_for(action),
      recorded_at: Time.current
    )
  end

  def change_log_for(action)
    if action == "destroy"
      attributes
    else
      previous_changes.except(:updated_at, :created_at)
    end
  end
end
