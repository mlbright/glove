class CreateImportBatches < ActiveRecord::Migration[8.1]
  def change
    create_table :import_batches do |t|
      t.references :user, null: false, foreign_key: true
      t.references :import_template, null: false, foreign_key: true
      t.integer :status, null: false, default: 0
      t.string :source_filename
      t.integer :processed_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.text :notes
      t.datetime :started_at
      t.datetime :finished_at
      t.json :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :import_batches, :status
  end
end
