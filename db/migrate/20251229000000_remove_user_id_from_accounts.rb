# frozen_string_literal: true

class RemoveUserIdFromAccounts < ActiveRecord::Migration[8.1]
  def change
    remove_index :accounts, column: [ :user_id, :name ], name: "index_accounts_on_user_id_and_name"
    remove_index :accounts, column: :user_id, name: "index_accounts_on_user_id"
    remove_column :accounts, :user_id, :integer, null: false

    # Add unique index on name alone (globally unique in single-tenant system)
    add_index :accounts, :name, unique: true
  end
end
