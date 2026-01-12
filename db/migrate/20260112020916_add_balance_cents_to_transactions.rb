class AddBalanceCentsToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :transactions, :balance_cents, :integer
  end
end
