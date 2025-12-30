class RemoveTransactionRevisionForeignKey < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :transaction_revisions, :transactions
  end
end
