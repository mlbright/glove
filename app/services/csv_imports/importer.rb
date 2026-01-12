# frozen_string_literal: true

module CsvImports
  # Service to import parsed CSV rows into the database as transactions
  class Importer
    ACCOUNT_FORMATS = {
      td_chequing: TdChequingParser,
      td_visa: TdVisaParser,
      mastercard: MastercardParser
    }.freeze

    # Formats that support balance reconciliation (have balance_cents in parsed rows)
    BALANCE_FORMATS = %i[td_chequing td_visa].freeze

    ImportResult = Data.define(:imported_count, :skipped_count, :error_count, :errors, :warnings, :skipped_duplicates)
    SkippedDuplicate = Data.define(:occurred_on, :description, :amount_cents, :entry_type)
    BalanceWarning = Data.define(:expected_balance_cents, :actual_balance_cents, :occurred_on, :message)

    def initialize(user:, account:, format:)
      @user = user
      @account = account
      @format = format.to_sym
    end

    def import(file_content)
      parser_class = ACCOUNT_FORMATS[@format]
      raise ArgumentError, "Unknown format: #{@format}" unless parser_class

      parser = parser_class.new(file_content)
      parse_result = parser.parse

      @imported_count = 0
      @skipped_count = 0
      @skipped_duplicates = []
      @warnings = []
      @error_count = parse_result.errors.count
      @errors = parse_result.errors.map { |e| "Parse error: #{e[:error]} (row: #{e[:row].join(', ')})" }

      return build_result if parse_result.rows.empty?

      # Sort rows chronologically for processing
      sorted_rows = sort_rows_chronologically(parse_result.rows)

      # For formats with balance data, perform balance reconciliation
      if supports_balance_reconciliation?
        perform_balance_reconciliation(sorted_rows)
      else
        # For Mastercard and other formats without balance, use simple import
        perform_simple_import(sorted_rows)
      end

      build_result
    end

    private

    def build_result
      ImportResult.new(
        imported_count: @imported_count,
        skipped_count: @skipped_count,
        error_count: @error_count,
        errors: @errors,
        warnings: @warnings,
        skipped_duplicates: @skipped_duplicates
      )
    end

    def supports_balance_reconciliation?
      BALANCE_FORMATS.include?(@format)
    end

    # Sort rows by date and row_index to get chronological order
    # TD Chequing: already chronological (oldest first), smallest row_index first for same date
    # TD Visa: reverse chronological in CSV, so we sort to get oldest first, largest row_index first for same date
    def sort_rows_chronologically(rows)
      if @format == :td_visa
        rows.sort_by { |r| [ r.occurred_at, r.respond_to?(:row_index) ? -r.row_index : 0 ] }
      else
        rows.sort_by { |r| [ r.occurred_at, r.respond_to?(:row_index) ? r.row_index : 0 ] }
      end
    end

    def perform_simple_import(sorted_rows)
      # Create opening balance if account is empty
      if @account.balance.zero? && sorted_rows.any?
        handle_opening_balance_result(create_opening_balance_transaction(sorted_rows))
      end

      sorted_rows.each do |row|
        handle_import_row_result(import_row(row))
      end
    end

    def perform_balance_reconciliation(sorted_rows)
      # If account has no transactions, create opening balance first (fresh import)
      if @account.transactions.empty?
        handle_opening_balance_result(create_opening_balance_transaction(sorted_rows))
        # Then import all rows with balance tracking
        sorted_rows.each do |row|
          if duplicate_exists?(row)
            @skipped_count += 1
            @skipped_duplicates << SkippedDuplicate.new(
              occurred_on: row.occurred_at,
              description: row.description,
              amount_cents: row.amount_cents,
              entry_type: row.entry_type
            )
          else
            handle_import_row_result(import_row_with_balance(row))
          end
        end
        return
      end

      # Find the oldest non-duplicate transaction in the import set
      oldest_new_row = find_oldest_non_duplicate(sorted_rows)

      if oldest_new_row.nil?
        # All rows are duplicates - nothing to import
        sorted_rows.each do |row|
          @skipped_count += 1
          @skipped_duplicates << SkippedDuplicate.new(
            occurred_on: row.occurred_at,
            description: row.description,
            amount_cents: row.amount_cents,
            entry_type: row.entry_type
          )
        end
        return
      end

      # Calculate expected balance before the oldest new transaction
      expected_balance_before = calculate_balance_before_row(oldest_new_row)
      actual_balance_before = calculate_actual_balance_before(oldest_new_row)

      # Check for balance mismatch and create adjustment if needed
      if expected_balance_before != actual_balance_before
        add_balance_warning(expected_balance_before, actual_balance_before, oldest_new_row.occurred_at)
        create_balance_adjustment(expected_balance_before, actual_balance_before, oldest_new_row.occurred_at)
      end

      # Import all non-duplicate transactions and update balance_cents
      import_with_balance_tracking(sorted_rows)

      # Replay existing transactions newer than oldest import to update their balance_cents
      replay_newer_transactions(oldest_new_row, sorted_rows)
    end

    # Find the oldest row that doesn't already exist in the account
    def find_oldest_non_duplicate(sorted_rows)
      sorted_rows.find { |row| !duplicate_exists?(row) }
    end

    def duplicate_exists?(row)
      # Check for duplicates based on date, amount, description, and entry_type
      base_query = @account.transactions.where(
        occurred_on: row.occurred_at,
        amount_cents: row.amount_cents,
        description: row.description,
        entry_type: row.entry_type
      )

      # If we find a match, check if it's a true duplicate
      existing = base_query.first
      return false unless existing

      # If existing transaction has no balance_cents, consider it a duplicate
      # (legacy transaction before balance tracking was added)
      return true if existing.balance_cents.nil?

      # If the row has balance_cents, it's a duplicate only if balance matches
      if row.respond_to?(:balance_cents) && row.balance_cents.present? && row.balance_cents != 0
        return existing.balance_cents == row.balance_cents
      end

      # If row has no balance_cents (e.g., Mastercard), match on basic fields only
      true
    end

    # Calculate what the balance should be BEFORE the given row based on the CSV data
    # This works backwards from the row's balance after the transaction
    def calculate_balance_before_row(row)
      if @format == :td_visa
        # TD Visa: balance = debt. Expense increases debt, income decreases it.
        if row.entry_type == :income
          row.balance_cents + row.amount_cents
        else
          row.balance_cents - row.amount_cents
        end
      else
        # TD Chequing: balance = funds. Income increases it, expense decreases it.
        if row.entry_type == :income
          row.balance_cents - row.amount_cents
        else
          row.balance_cents + row.amount_cents
        end
      end
    end

    # Calculate the actual account balance from existing transactions before a given date
    def calculate_actual_balance_before(row)
      # Get all transactions before this row's date
      existing_before = @account.transactions.where("occurred_on < ?", row.occurred_at)

      # For same-day transactions, we need to consider row ordering
      # Include same-day transactions that would come before this row
      same_day_before = @account.transactions
        .where("DATE(occurred_on) = ?", row.occurred_at.to_date)
        .where.not(balance_cents: nil)
        .order(:balance_cents)

      # If we have balance_cents on existing transactions, use the most recent one
      last_with_balance = @account.transactions
        .where("occurred_on < ?", row.occurred_at)
        .where.not(balance_cents: nil)
        .order(occurred_on: :desc, id: :desc)
        .first

      if last_with_balance
        last_with_balance.balance_cents
      else
        # Calculate from scratch using all transactions before this date
        calculate_balance_from_transactions(existing_before)
      end
    end

    def calculate_balance_from_transactions(transactions)
      income_value = Transaction.entry_types[:income]
      transactions.sum do |t|
        t.entry_type == "income" ? t.amount_cents : -t.amount_cents
      end
    end

    def add_balance_warning(expected, actual, occurred_on)
      difference = expected - actual
      direction = difference > 0 ? "higher" : "lower"

      @warnings << BalanceWarning.new(
        expected_balance_cents: expected,
        actual_balance_cents: actual,
        occurred_on: occurred_on,
        message: "Balance mismatch detected: imported file shows balance should be #{Money.new(expected, :cad).format} " \
                 "but account balance is #{Money.new(actual, :cad).format} " \
                 "(#{Money.new(difference.abs, :cad).format} #{direction}). " \
                 "A Balance Adjustment transaction has been created."
      )
    end

    def create_balance_adjustment(expected, actual, occurred_on)
      difference = expected - actual

      # Determine entry type based on format and difference direction
      entry_type = if @format == :td_visa
        # TD Visa: positive difference means we need more debt (expense), negative means less debt (income)
        difference > 0 ? :expense : :income
      else
        # Chequing: positive difference means we need more funds (income), negative means less (expense)
        difference > 0 ? :income : :expense
      end

      transaction = @account.transactions.build(
        occurred_on: occurred_on,
        amount_cents: difference.abs,
        entry_type: entry_type,
        description: "Balance Adjustment",
        status: :cleared,
        balance_cents: nil # Will be set during replay
      )
      transaction.acted_by = @user

      if transaction.save
        @imported_count += 1
      else
        @error_count += 1
        @errors << "Failed to create balance adjustment: #{transaction.errors.full_messages.join(', ')}"
      end
    end

    def import_with_balance_tracking(sorted_rows)
      sorted_rows.each do |row|
        if duplicate_exists?(row)
          @skipped_count += 1
          @skipped_duplicates << SkippedDuplicate.new(
            occurred_on: row.occurred_at,
            description: row.description,
            amount_cents: row.amount_cents,
            entry_type: row.entry_type
          )
        else
          result = import_row_with_balance(row)
          handle_import_row_result(result)
        end
      end
    end

    def import_row_with_balance(row)
      transaction = @account.transactions.build(
        occurred_on: row.occurred_at,
        amount_cents: row.amount_cents,
        entry_type: row.entry_type,
        description: row.description,
        status: :cleared,
        balance_cents: row.respond_to?(:balance_cents) ? row.balance_cents : nil
      )
      transaction.acted_by = @user

      if transaction.save
        :imported
      else
        "Failed to save transaction: #{transaction.errors.full_messages.join(', ')} (#{row.description} on #{row.occurred_at})"
      end
    rescue StandardError => e
      "Error importing row: #{e.message} (#{row.description} on #{row.occurred_at})"
    end

    # Replay existing transactions that are newer than the oldest import row
    # to recalculate their balance_cents based on the imported data
    def replay_newer_transactions(oldest_import_row, sorted_import_rows)
      # Get the newest imported row to find its balance
      newest_import_row = sorted_import_rows.reverse.find { |r| !duplicate_exists_excluding_just_imported?(r) }
      return unless newest_import_row

      # Find existing transactions that are newer than our newest import
      # These need their balance_cents updated
      newer_existing = @account.transactions
        .where("occurred_on > ?", newest_import_row.occurred_at)
        .where.not(description: [ "Balance Adjustment", "Opening Balance" ])
        .order(:occurred_on, :id)

      return if newer_existing.empty?

      # Start from the newest imported balance and replay forward
      running_balance = newest_import_row.balance_cents

      newer_existing.each do |transaction|
        # Calculate new balance after this transaction
        running_balance = if @format == :td_visa
          transaction.income? ? running_balance - transaction.amount_cents : running_balance + transaction.amount_cents
        else
          transaction.income? ? running_balance + transaction.amount_cents : running_balance - transaction.amount_cents
        end

        transaction.update_column(:balance_cents, running_balance)
      end
    end

    def duplicate_exists_excluding_just_imported?(row)
      # For replay logic, check if transaction exists but wasn't just imported
      @account.transactions.where(
        occurred_on: row.occurred_at,
        amount_cents: row.amount_cents,
        description: row.description,
        balance_cents: row.balance_cents
      ).where("created_at < ?", 1.minute.ago).exists?
    end

    def handle_opening_balance_result(result)
      case result
      when :imported
        @imported_count += 1
      when :skipped
        @skipped_count += 1
      when String
        @error_count += 1
        @errors << result
      end
    end

    def handle_import_row_result(result)
      case result
      when :imported
        @imported_count += 1
      when SkippedDuplicate
        @skipped_count += 1
        @skipped_duplicates << result
      when :skipped
        @skipped_count += 1
      else
        @error_count += 1
        @errors << result
      end
    end

    private

    # Creates an opening balance transaction based on the earliest row in the CSV.
    # The opening balance is calculated by working backwards from the balance after that transaction.
    #
    # CSV sort order varies by format:
    # - TD Visa (credit card): reverse chronological (newest first, oldest last)
    #   → For same-date rows, highest row_index = oldest
    # - TD Chequing: chronological (oldest first, newest last)
    #   → For same-date rows, lowest row_index = oldest
    def create_opening_balance_transaction(rows)
      # Find the earliest row based on format's sort order
      earliest_row = if @format == :td_visa
        # Reverse chronological: min date, max row_index for same-date rows
        rows.min_by { |r| [ r.occurred_at, r.respond_to?(:row_index) ? -r.row_index : 0 ] }
      else
        # Chronological (td_chequing): min date, min row_index for same-date rows
        rows.min_by { |r| [ r.occurred_at, r.respond_to?(:row_index) ? r.row_index : 0 ] }
      end

      # Skip if the CSV format doesn't include balance (e.g., Mastercard)
      return :skipped if earliest_row.balance_cents.zero? && earliest_row.amount_cents.zero?
      return :skipped if earliest_row.balance_cents.zero?

      # Calculate opening balance: balance after transaction minus the transaction's effect
      opening_balance_cents = calculate_balance_before_row(earliest_row)

      return :skipped if opening_balance_cents.zero?

      # Check for existing opening balance transaction (match on date only for opening balance)
      existing = @account.transactions.where(description: "Opening Balance")
                         .where("date(occurred_on) = ?", earliest_row.occurred_at.to_date)
                         .exists?
      return :skipped if existing

      # Determine entry type based on whether opening balance is positive or negative
      # For TD Visa: positive balance = debt (expense), negative = credit (income)
      # For other formats: positive = income, negative = expense
      entry_type = if @format == :td_visa
        opening_balance_cents >= 0 ? :expense : :income
      else
        opening_balance_cents >= 0 ? :income : :expense
      end

      transaction = @account.transactions.build(
        occurred_on: earliest_row.occurred_at,
        amount_cents: opening_balance_cents.abs,
        entry_type: entry_type,
        description: "Opening Balance",
        status: :cleared
      )
      transaction.acted_by = @user

      if transaction.save
        :imported
      else
        "Failed to create opening balance: #{transaction.errors.full_messages.join(', ')}"
      end
    rescue StandardError => e
      "Error creating opening balance: #{e.message}"
    end

    def import_row(row)
      # Check for duplicates based on datetime, amount, description, and balance_cents
      if duplicate_exists?(row)
        return SkippedDuplicate.new(
          occurred_on: row.occurred_at,
          description: row.description,
          amount_cents: row.amount_cents,
          entry_type: row.entry_type
        )
      end

      transaction = @account.transactions.build(
        occurred_on: row.occurred_at,
        amount_cents: row.amount_cents,
        entry_type: row.entry_type,
        description: row.description,
        status: :cleared,
        balance_cents: row.respond_to?(:balance_cents) ? row.balance_cents : nil
      )
      transaction.acted_by = @user

      if transaction.save
        :imported
      else
        "Failed to save transaction: #{transaction.errors.full_messages.join(', ')} (#{row.description} on #{row.occurred_at})"
      end
    rescue StandardError => e
      "Error importing row: #{e.message} (#{row.description} on #{row.occurred_at})"
    end
  end
end
