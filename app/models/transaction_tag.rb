class TransactionTag < ApplicationRecord
  belongs_to :transaction_record, class_name: "Transaction", foreign_key: :transaction_id, inverse_of: :transaction_tags
  belongs_to :tag

  validates :tag_id, uniqueness: { scope: :transaction_id }
end
