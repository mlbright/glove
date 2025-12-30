class CreateTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :transactions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.references :schedule, foreign_key: true
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.integer :entry_type, null: false, default: 0
      t.date :occurred_on, null: false
      t.text :memo
      t.references :import_batch, foreign_key: true
      t.integer :status, null: false, default: 0
      t.text :notes
      t.string :external_id

      t.timestamps
    end

    add_index :transactions, [ :user_id, :occurred_on ]
    add_index :transactions, [ :account_id, :occurred_on ]
    add_index :transactions, :entry_type
  end
end
