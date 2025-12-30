# frozen_string_literal: true

require "csv"
require "bigdecimal"

module CsvImports
  # Parser for Mastercard credit card CSV exports
  # Expects the .csv file export from the "transactions" tab on the PC Financial website
  # Expected format (quoted CSV with headers):
  #   "Description","Type","Card Holder Name","Date","Time","Amount"
  #   "TIM HORTONS #1723","PURCHASE","JOHN DOE","12/11/2025","01:35 AM","-1.92"
  # Columns: description, type, cardholder, date, time, amount
  # Note: Date format is MM/DD/YYYY, Time is HH:MM AM/PM, Amount is negative for purchases
  class MastercardParser
    DATE_FORMAT = "%m/%d/%Y"
    TIME_FORMAT = "%I:%M %p"
    DATETIME_FORMAT = "%m/%d/%Y %I:%M %p"

    ParsedRow = Data.define(:occurred_at, :description, :amount_cents, :entry_type, :balance_cents)

    def initialize(file_content)
      @file_content = file_content
    end

    def parse
      rows = []
      errors = []

      CSV.parse(@file_content, headers: true) do |row|
        next if row.fields.all?(&:blank?)

        begin
          parsed = parse_row(row)
          rows << parsed if parsed
        rescue StandardError => e
          errors << { row: row.to_h, error: e.message }
        end
      end

      Result.new(rows: rows, errors: errors)
    end

    private

    def parse_row(row)
      description = row["Description"]&.strip
      transaction_type = row["Type"]&.strip&.upcase
      date_str = row["Date"]&.strip
      time_str = row["Time"]&.strip
      amount_str = row["Amount"]&.strip

      return nil if date_str.blank?

      occurred_at = parse_datetime(date_str, time_str)
      amount = parse_money(amount_str)

      # Determine entry type based on amount sign
      # Negative amounts = purchases (expense)
      # Positive amounts = payments/credits (income)
      if amount < 0
        entry_type = :expense
        amount_cents = (amount.abs * 100).to_i
      else
        entry_type = :income
        amount_cents = (amount * 100).to_i
      end

      # Include transaction type in description if it's not a standard purchase
      full_description = if transaction_type.present? && transaction_type != "PURCHASE"
        "#{description} (#{transaction_type})"
      else
        description.to_s
      end

      ParsedRow.new(
        occurred_at: occurred_at,
        description: full_description,
        amount_cents: amount_cents,
        entry_type: entry_type,
        balance_cents: 0 # Mastercard CSV doesn't include balance
      )
    end

    def parse_datetime(date_str, time_str)
      if time_str.present?
        datetime_str = "#{date_str} #{time_str}"
        Time.strptime(datetime_str, DATETIME_FORMAT)
      else
        Date.strptime(date_str, DATE_FORMAT).to_time
      end
    rescue Date::Error, ArgumentError
      raise "Invalid date/time format: #{date_str} #{time_str}. Expected MM/DD/YYYY HH:MM AM/PM"
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
