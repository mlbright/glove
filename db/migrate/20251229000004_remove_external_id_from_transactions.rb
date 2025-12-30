class RemoveExternalIdFromTransactions < ActiveRecord::Migration[8.0]
  def change
    remove_column :transactions, :external_id, :string
  end
end
