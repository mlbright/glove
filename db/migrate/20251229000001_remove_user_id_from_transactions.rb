# frozen_string_literal: true

class RemoveUserIdFromTransactions < ActiveRecord::Migration[8.1]
  def change
    remove_index :transactions, :user_id
    remove_column :transactions, :user_id, :integer, null: false
  end
end
