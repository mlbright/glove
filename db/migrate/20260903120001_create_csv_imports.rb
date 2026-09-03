class CreateCsvImports < ActiveRecord::Migration[8.1]
  def change
    create_table :csv_imports do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :filename, null: false
      # SHA-256 of the uploaded bytes. Provenance for the rows this import
      # created, and deliberately not part of how rows are matched.
      t.string :digest, null: false

      t.timestamps
    end

    add_index :csv_imports, :digest
  end
end
