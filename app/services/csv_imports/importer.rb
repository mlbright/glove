# frozen_string_literal: true

module CsvImports
  # Service to import parsed CSV rows into the database as transactions
  class Importer
    ACCOUNT_FORMATS = {
      td_chequing: TdChequingParser,
      td_visa: TdVisaParser,
      mastercard: MastercardParser
    }.freeze

    ImportResult = Data.define(:imported_count, :skipped_count, :error_count, :errors, :skipped_duplicates)
    SkippedDuplicate = Data.define(:occurred_on, :description, :amount_cents, :entry_type)

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

      imported_count = 0
      skipped_count = 0
      skipped_duplicates = []
      error_count = parse_result.errors.count
      errors = parse_result.errors.map { |e| "Parse error: #{e[:error]} (row: #{e[:row].join(', ')})" }

      # Create opening balance transaction if account has zero balance
      if @account.balance.zero? && parse_result.rows.any?
        result = create_opening_balance_transaction(parse_result.rows)
        case result
        when :imported
          imported_count += 1
        when :skipped
          skipped_count += 1
        when String
          error_count += 1
          errors << result
        end
      end

      parse_result.rows.each do |row|
        result = import_row(row)
        case result
        when :imported
          imported_count += 1
        when SkippedDuplicate
          skipped_count += 1
          skipped_duplicates << result
        when :skipped
          skipped_count += 1
        else
          error_count += 1
          errors << result
        end
      end

      ImportResult.new(
        imported_count: imported_count,
        skipped_count: skipped_count,
        error_count: error_count,
        errors: errors,
        skipped_duplicates: skipped_duplicates
      )
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
      # TD Visa: balance = debt, so purchases increase it, payments decrease it
      #   For expense (purchase): opening = balance - amount
      #   For income (payment): opening = balance + amount
      # Other formats: balance = funds, so income increases it, expenses decrease it
      #   For income: opening = balance - amount
      #   For expense: opening = balance + amount
      opening_balance_cents = if @format == :td_visa
        if earliest_row.entry_type == :income
          earliest_row.balance_cents + earliest_row.amount_cents
        else
          earliest_row.balance_cents - earliest_row.amount_cents
        end
      else
        if earliest_row.entry_type == :income
          earliest_row.balance_cents - earliest_row.amount_cents
        else
          earliest_row.balance_cents + earliest_row.amount_cents
        end
      end

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
      # Check for duplicates based on datetime, amount, and description
      # This helps avoid reimporting the same transactions
      existing = @account.transactions.find_by(
        occurred_on: row.occurred_at,
        amount_cents: row.amount_cents,
        description: row.description
      )

      if existing
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
        status: :cleared
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
