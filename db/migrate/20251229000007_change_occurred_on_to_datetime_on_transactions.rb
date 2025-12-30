class ChangeOccurredOnToDatetimeOnTransactions < ActiveRecord::Migration[8.0]
  def up
    # Add new datetime column
    add_column :transactions, :occurred_at, :datetime

    # Copy date values to datetime (at midnight)
    execute <<-SQL
      UPDATE transactions SET occurred_at = datetime(occurred_on)
    SQL

    # Make occurred_at not null
    change_column_null :transactions, :occurred_at, false

    # Remove old date column
    remove_column :transactions, :occurred_on

    # Rename new column to occurred_on
    rename_column :transactions, :occurred_at, :occurred_on
  end

  def down
    # Add date column back
    add_column :transactions, :occurred_on_date, :date

    # Copy datetime to date
    execute <<-SQL
      UPDATE transactions SET occurred_on_date = date(occurred_on)
    SQL

    # Make date not null
    change_column_null :transactions, :occurred_on_date, false

    # Remove datetime column
    remove_column :transactions, :occurred_on

    # Rename date column
    rename_column :transactions, :occurred_on_date, :occurred_on
  end
end
