class TransactionRevision < ApplicationRecord
  belongs_to :transaction_record, class_name: "Transaction", foreign_key: :transaction_id, inverse_of: :transaction_revisions
  belongs_to :user

  validates :action, :recorded_at, presence: true
end
