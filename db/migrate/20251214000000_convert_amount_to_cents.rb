# frozen_string_literal: true

class ConvertAmountToCents < ActiveRecord::Migration[8.1]
  def up
    # Add the new amount_cents column
    add_column :transactions, :amount_cents, :integer

    # Convert existing decimal amounts to cents
    execute <<-SQL
      UPDATE transactions
      SET amount_cents = CAST(ROUND(amount * 100) AS INTEGER)
    SQL

    # Make amount_cents not null after data migration
    change_column_null :transactions, :amount_cents, false

    # Remove the old decimal column
    remove_column :transactions, :amount
  end

  def down
    # Add back the decimal column
    add_column :transactions, :amount, :decimal, precision: 12, scale: 2

    # Convert cents back to decimal
    execute <<-SQL
      UPDATE transactions
      SET amount = amount_cents / 100.0
    SQL

    # Make amount not null
    change_column_null :transactions, :amount, false

    # Remove the cents column
    remove_column :transactions, :amount_cents
  end
end
