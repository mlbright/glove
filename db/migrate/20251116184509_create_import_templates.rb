class CreateImportTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :import_templates do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :delimiter, null: false, default: ","
      t.boolean :header, null: false, default: true
      t.json :mapping, null: false, default: {}
      t.json :column_examples

      t.timestamps
    end

    add_index :import_templates, [ :user_id, :name ], unique: true
  end
end
