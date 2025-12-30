# frozen_string_literal: true

require "csv"
require "bigdecimal"

module CsvImports
  # Parser for TD Canada Trust Chequing account CSV exports
  # Expected format (quoted CSV):
  #   "2025-11-14","ACME Corp  PAY",,"1000.00","1500.00"
  # Columns: date, description, debit, credit, balance
  class TdChequingParser
    DATE_FORMAT = "%Y-%m-%d"

    ParsedRow = Data.define(:occurred_at, :description, :amount_cents, :entry_type, :balance_cents, :row_index)

    def initialize(file_content)
      @file_content = file_content
    end

    def parse
      rows = []
      errors = []
      index = 0

      CSV.parse(@file_content, headers: false) do |row|
        next if row.all?(&:blank?)

        begin
          parsed = parse_row(row, index)
          rows << parsed if parsed
          index += 1
        rescue StandardError => e
          errors << { row: row.to_a, error: e.message }
          index += 1
        end
      end

      Result.new(rows: rows, errors: errors)
    end

    private

    def parse_row(row, index)
      date_str, description, debit_str, credit_str, balance_str = row.map { |v| v&.strip }

      return nil if date_str.blank?

      occurred_at = parse_date(date_str).to_time
      description = description.to_s.strip

      # Parse amounts using BigDecimal for precision
      debit = parse_money(debit_str)
      credit = parse_money(credit_str)
      balance = parse_money(balance_str)

      # Determine entry type and amount
      # Debit = money leaving account (expense)
      # Credit = money entering account (income)
      if credit > 0
        entry_type = :income
        amount_cents = (credit * 100).to_i
      elsif debit > 0
        entry_type = :expense
        amount_cents = (debit * 100).to_i
      else
        raise "No valid amount found"
      end

      balance_cents = (balance * 100).to_i

      ParsedRow.new(
        occurred_at: occurred_at,
        description: description,
        amount_cents: amount_cents,
        entry_type: entry_type,
        balance_cents: balance_cents,
        row_index: index
      )
    end

    def parse_date(date_str)
      Date.strptime(date_str, DATE_FORMAT)
    rescue Date::Error
      raise "Invalid date format: #{date_str}. Expected YYYY-MM-DD"
    end

    def parse_money(value)
      return BigDecimal("0") if value.blank?

      # Remove any currency symbols, commas, and whitespace
      cleaned = value.to_s.gsub(/[$,\s]/, "")
      return BigDecimal("0") if cleaned.empty?

      BigDecimal(cleaned)
    rescue ArgumentError
      raise "Invalid money value: #{value}"
    end
  end
end
