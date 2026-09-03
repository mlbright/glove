class GeneralizeTransactionRevisions < ActiveRecord::Migration[8.1]
  # Checkpoints need an audit trail for the same reason transactions do — the
  # balance hangs off a checkpoint's number — so the revision table stops being
  # about transactions specifically. See docs/adr/0002.
  def up
    rename_table :transaction_revisions, :revisions
    rename_column :revisions, :transaction_id, :record_id

    add_column :revisions, :record_type, :string
    execute "UPDATE revisions SET record_type = 'Transaction'"
    change_column_null :revisions, :record_type, false

    remove_index :revisions, column: [ :record_id, :recorded_at ] if index_exists?(:revisions, [ :record_id, :recorded_at ])
    remove_index :revisions, column: :record_id if index_exists?(:revisions, :record_id)
    add_index :revisions, [ :record_type, :record_id, :recorded_at ]
  end

  def down
    remove_index :revisions, column: [ :record_type, :record_id, :recorded_at ]
    execute "DELETE FROM revisions WHERE record_type <> 'Transaction'"
    remove_column :revisions, :record_type
    rename_column :revisions, :record_id, :transaction_id
    rename_table :revisions, :transaction_revisions
    add_index :transaction_revisions, :transaction_id
    add_index :transaction_revisions, [ :transaction_id, :recorded_at ]
  end
end
