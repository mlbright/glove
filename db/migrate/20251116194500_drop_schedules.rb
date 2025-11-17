class DropSchedules < ActiveRecord::Migration[8.1]
  def change
    if column_exists?(:transactions, :schedule_id)
      remove_reference :transactions, :schedule, foreign_key: true
    end

    drop_table :schedules do |t|
      t.references :user, null: false, foreign_key: true
      t.references :account, foreign_key: true
      t.string :name, null: false
      t.integer :frequency, null: false, default: 0
      t.integer :interval_value, null: false, default: 1
      t.date :next_occurs_on, null: false
      t.boolean :active, null: false, default: true
      t.json :metadata
      t.timestamps
    end
  end
end
