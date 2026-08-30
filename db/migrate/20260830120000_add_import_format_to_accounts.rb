class AddImportFormatToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :import_format, :string

    # Dead since it was re-added: never written by the app, never read, all zeroes.
    # Import format, not account type, decides which parser an account's CSV gets.
    remove_column :accounts, :account_type, :integer
  end
end
