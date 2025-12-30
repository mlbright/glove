class RemoveOpeningBalanceFromTransactions < ActiveRecord::Migration[8.0]
  def change
    remove_column :transactions, :opening_balance, :boolean, default: false, null: false
  end
end
