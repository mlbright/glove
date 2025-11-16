class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :account_type, null: false, default: 0
      t.string :color
      t.text :description
      t.datetime :archived_at

      t.timestamps
    end

    add_index :accounts, [:user_id, :name], unique: true
  end
end
