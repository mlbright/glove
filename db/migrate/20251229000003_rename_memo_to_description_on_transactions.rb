class RenameMemoToDescriptionOnTransactions < ActiveRecord::Migration[8.0]
  def change
    rename_column :transactions, :memo, :description
  end
end
