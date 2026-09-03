class MigrateOpeningBalancesToCheckpoints < ActiveRecord::Migration[8.1]
  # The synthetic "Opening Balance" transactions become the earliest checkpoint
  # of their account. Each was computed as the balance before its account's
  # first imported row, so it asserts the closing balance of the preceding day.
  #
  # They have to go rather than stay: an Opening Balance row is dated on or
  # after the checkpoint it becomes, so leaving it in place would count the
  # anchor twice. Their revisions are left behind deliberately — the history of
  # how a row came to exist outlives the row. See docs/adr/0002.
  #
  # Raw SQL, and no revision rows of its own, following the precedent set by
  # BackfillAccountImportFormats: a migration has no acting user to attribute.
  DESCRIPTION = "Opening Balance"

  def up
    # entry_type 0 is income, so a positive opening balance is funds held and a
    # negative one is debt — the sign convention Account#balance reports in.
    # source 0 is "derived": these came from TD's own balance column, and
    # nobody has yet held one against a statement.
    execute ActiveRecord::Base.sanitize_sql_array([ <<~SQL, DESCRIPTION ])
      INSERT INTO checkpoints (account_id, closed_on, balance_cents, source, created_at, updated_at)
      SELECT account_id,
             DATE(occurred_on, '-1 day'),
             CASE WHEN entry_type = 0 THEN amount_cents ELSE -amount_cents END,
             0,
             CURRENT_TIMESTAMP,
             CURRENT_TIMESTAMP
        FROM transactions
       WHERE description = ?
         AND NOT EXISTS (
               SELECT 1
                 FROM checkpoints
                WHERE checkpoints.account_id = transactions.account_id
                  AND checkpoints.closed_on = DATE(transactions.occurred_on, '-1 day')
             )
    SQL

    execute ActiveRecord::Base.sanitize_sql_array([
      "DELETE FROM transactions WHERE description = ?", DESCRIPTION
    ])
  end

  def down
    # Nothing to undo: rolling back past this point drops the checkpoints table
    # outright, and the transactions these replaced were synthetic to begin with.
  end
end
