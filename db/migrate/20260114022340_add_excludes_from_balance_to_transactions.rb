class AddExcludesFromBalanceToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :transactions, :excludes_from_balance, :boolean, default: false, null: false
  end
end
