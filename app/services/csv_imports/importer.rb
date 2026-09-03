# frozen_string_literal: true

module CsvImports
  # Imports a bank's CSV export into an account as transactions.
  #
  # Two things this no longer does, both of them removed by ADR 2. It does not
  # create a synthetic "Opening Balance" transaction: an opening balance is the
  # earliest checkpoint, and a transaction standing in for prior history is
  # silently invalidated the moment older history is imported behind it. And it
  # does not rewrite the balance_cents of rows it did not import: that column
  # records the balance the bank printed on a row, and replaying over it
  # destroyed the only independent number the file carried.
  #
  # What replaces the old whole-account balance warning is the checkpoint audit,
  # which reports a discrepancy inside the interval that contains it.
  class Importer
    ImportResult = Data.define(
      :imported_count, :skipped_count, :error_count, :errors, :skipped_duplicates,
      :derived_checkpoint, :suggested_checkpoint
    )
    SkippedDuplicate = Data.define(:occurred_on, :description, :amount_cents, :entry_type)

    # The closing balance the file itself asserts for its last day. Offered, not
    # recorded: only a person holding the statement can promote it.
    SuggestedCheckpoint = Data.define(:closed_on, :balance_cents)

    def initialize(user:, account:, import_format:, csv_import: nil)
      @user = user
      @account = account
      @import_format = import_format.to_s
      @csv_import = csv_import
    end

    def import(file_content)
      parse_result = Format.parser_for(@import_format).new(file_content).parse

      @imported_count = 0
      @skipped_count = 0
      @skipped_duplicates = []
      @derived_checkpoint = nil
      @suggested_checkpoint = nil
      @error_count = parse_result.errors.count
      @errors = parse_result.errors.map { |e| "Parse error: #{e[:error]} (row: #{e[:row].join(', ')})" }

      return build_result if parse_result.rows.empty?

      rows = sort_rows_chronologically(parse_result.rows)

      @derived_checkpoint = derive_opening_checkpoint(rows)
      import_rows(rows)
      @suggested_checkpoint = suggest_closing_checkpoint(rows)

      build_result
    end

    private

    def build_result
      ImportResult.new(
        imported_count: @imported_count,
        skipped_count: @skipped_count,
        error_count: @error_count,
        errors: @errors,
        skipped_duplicates: @skipped_duplicates,
        derived_checkpoint: @derived_checkpoint,
        suggested_checkpoint: @suggested_checkpoint
      )
    end

    def format_definition = Format.fetch(@import_format)

    # Sort rows into the order they happened.
    # TD Chequing and Mastercard: already chronological, smallest row_index first.
    # TD Visa: reverse chronological in the CSV, so same-date rows run backwards.
    def sort_rows_chronologically(rows)
      if @import_format == "td_visa"
        rows.sort_by { |r| [ r.occurred_at, -row_index(r) ] }
      else
        rows.sort_by { |r| [ r.occurred_at, row_index(r) ] }
      end
    end

    def row_index(row) = row.respond_to?(:row_index) && row.row_index ? row.row_index : 0

    def import_rows(rows)
      matcher = RowMatcher.new(@account)

      rows.each do |row|
        if matcher.new_occurrence?(row)
          handle_import_row_result(import_row(row))
        else
          @skipped_count += 1
          @skipped_duplicates << SkippedDuplicate.new(
            occurred_on: row.occurred_at,
            description: row.description,
            amount_cents: row.amount_cents,
            entry_type: row.entry_type
          )
        end
      end
    end

    def import_row(row)
      transaction = @account.transactions.build(
        occurred_on: row.occurred_at,
        amount_cents: row.amount_cents,
        entry_type: row.entry_type,
        description: row.description,
        status: :cleared,
        balance_cents: row.balance_cents,
        csv_import: @csv_import,
        import_row_number: row.respond_to?(:row_index) && row.row_index ? row.row_index + 1 : nil
      )
      transaction.acted_by = @user

      return :imported if transaction.save

      "Failed to save transaction: #{transaction.errors.full_messages.join(', ')} (#{row.description} on #{row.occurred_at})"
    rescue StandardError => e
      "Error importing row: #{e.message} (#{row.description} on #{row.occurred_at})"
    end

    # An account being imported into for the first time gets its opening
    # balance from the bank's own balance column: the balance before the
    # earliest row is the closing balance of the day before it.
    #
    # Only for an account holding nothing at all. Deriving an anchor for an
    # account that already has history is how the old opening balance came to
    # contradict the rows behind it.
    def derive_opening_checkpoint(rows)
      return unless format_definition.reconciles_balance?
      return if @account.checkpoints.any? || @account.transactions.any?

      earliest = rows.first
      return if earliest.balance_cents.nil?

      checkpoint = @account.checkpoints.build(
        closed_on: date_of(earliest) - 1,
        balance_cents: balance_before(earliest),
        source: :derived
      )
      checkpoint.acted_by = @user
      checkpoint.save ? checkpoint : nil
    end

    # The balance the bank reports on a row is the account after that row. Undo
    # the row's own effect to get the closing balance it was measured from.
    def balance_before(row)
      format_definition.signed_balance_cents(row.balance_cents) - signed_amount(row)
    end

    def signed_amount(row)
      row.entry_type == :income ? row.amount_cents : -row.amount_cents
    end

    # What the file says the account closed at on its last day. Never recorded
    # on its own: a mismatch is reported and never repaired silently, and this
    # number is only as good as the file's coverage of that day.
    def suggest_closing_checkpoint(rows)
      return unless format_definition.reconciles_balance?

      latest = rows.last
      return if latest.balance_cents.nil?

      closed_on = date_of(latest)
      return if @account.checkpoints.exists?(closed_on: closed_on)

      SuggestedCheckpoint.new(
        closed_on: closed_on,
        balance_cents: format_definition.signed_balance_cents(latest.balance_cents)
      )
    end

    def date_of(row) = row.occurred_at.in_time_zone.to_date

    def handle_import_row_result(result)
      if result == :imported
        @imported_count += 1
      else
        @error_count += 1
        @errors << result
      end
    end
  end
end
