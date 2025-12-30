class AddOpeningBalanceToTransactions < ActiveRecord::Migration[8.0]
  def change
    add_column :transactions, :opening_balance, :boolean, default: false, null: false
  end
end
