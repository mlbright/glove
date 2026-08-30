class BackfillAccountImportFormats < ActiveRecord::Migration[8.1]
  # The accounts that predate import format becoming a property of the account.
  # Matched on exact name; anything unmatched (the archived test accounts) is
  # left null, which means "not importable until someone sets a format".
  FORMATS_BY_NAME = {
    "PC Financial Mastercard" => "mastercard",
    "TD personal VISA" => "td_visa",
    "TD joint chequing" => "td_chequing",
    "TD personal chequing" => "td_chequing",
    "TD joint savings" => "td_chequing"
  }.freeze

  def up
    FORMATS_BY_NAME.each do |name, import_format|
      execute ActiveRecord::Base.sanitize_sql_array([
        "UPDATE accounts SET import_format = ? WHERE name = ? AND import_format IS NULL",
        import_format, name
      ])
    end
  end

  def down
    # Nothing to undo: rolling back past this point drops the column outright.
  end
end
