class AddImportProvenanceToTransactions < ActiveRecord::Migration[8.1]
  def change
    # Where the row came from. Recorded so an imported row can be traced back to
    # the file and line that produced it; not part of the matching key, because
    # statement exports overlap and the same purchase sits at different offsets
    # in successive files. See docs/adr/0002.
    add_reference :transactions, :csv_import, foreign_key: true, null: true
    add_column :transactions, :import_row_number, :integer

    # Set on an adjustment transaction, naming the checkpoint whose interval it
    # was created to close. Kept so a later checkpoint edit can flag the
    # adjustment as stale rather than silently removing it.
    add_reference :transactions, :adjusts_checkpoint, foreign_key: { to_table: :checkpoints }, null: true
  end
end
