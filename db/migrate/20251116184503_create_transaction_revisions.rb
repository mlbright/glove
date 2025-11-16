class CreateTransactionRevisions < ActiveRecord::Migration[8.1]
  def change
    create_table :transaction_revisions do |t|
      t.references :transaction, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :action, null: false
      t.json :change_log, null: false, default: {}
      t.datetime :recorded_at, null: false

      t.timestamps
    end

    add_index :transaction_revisions, [:transaction_id, :recorded_at]
  end
end
