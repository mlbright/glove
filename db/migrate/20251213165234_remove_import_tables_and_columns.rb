class RemoveImportTablesAndColumns < ActiveRecord::Migration[8.1]
  def change
    # Remove the foreign key column from transactions first
    remove_column :transactions, :import_batch_id, :integer, if_exists: true

    # Drop the import_batches table
    drop_table :import_batches, if_exists: true do |t|
      t.integer :user_id, null: false
      t.integer :import_template_id, null: false
      t.integer :status, default: 0, null: false
      t.string :source_filename
      t.text :notes
      t.json :metadata, default: {}, null: false
      t.integer :processed_count, default: 0, null: false
      t.integer :failed_count, default: 0, null: false
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end

    # Drop the import_templates table
    drop_table :import_templates, if_exists: true do |t|
      t.integer :user_id, null: false
      t.string :name, null: false
      t.string :delimiter, default: ",", null: false
      t.boolean :header, default: true, null: false
      t.json :mapping, default: {}, null: false
      t.json :column_examples
      t.timestamps
    end
  end
end
