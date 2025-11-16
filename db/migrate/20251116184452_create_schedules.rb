class CreateSchedules < ActiveRecord::Migration[8.1]
  def change
    create_table :schedules do |t|
      t.references :user, null: false, foreign_key: true
      t.references :account, foreign_key: true
      t.string :name, null: false
      t.integer :frequency, null: false, default: 0
      t.integer :interval_value, null: false, default: 1
      t.date :next_occurs_on, null: false
      t.json :metadata
      t.boolean :active, null: false, default: true

      t.timestamps
    end
  end
end
