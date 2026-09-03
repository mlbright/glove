class CreateCheckpoints < ActiveRecord::Migration[8.1]
  def change
    create_table :checkpoints do |t|
      t.references :account, null: false, foreign_key: true
      # The date the account closed at this amount. A date, not a datetime:
      # a checkpoint is an end-of-day closing balance, the number a statement
      # already prints. See docs/adr/0002.
      t.date :closed_on, null: false
      # Signed the way Account#balance is: funds positive, debt negative.
      t.integer :balance_cents, null: false
      # derived: computed by the importer from a bank's own balance column.
      # verified: entered or corrected by a person holding a statement.
      t.integer :source, null: false, default: 0

      t.timestamps
    end

    # Two assertions about the same day's closing balance contradict each other.
    add_index :checkpoints, [ :account_id, :closed_on ], unique: true
  end
end
