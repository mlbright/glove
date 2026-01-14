class AddAccountTypeToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :account_type, :integer
  end
end
