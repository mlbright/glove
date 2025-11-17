# frozen_string_literal: true

require "csv"
require "bigdecimal"

module Transactions
  class Importer
    def initialize(batch)
      @batch = batch
      @user = batch.user
      @template = batch.import_template
    end

    def call
      @batch.update!(status: :processing, started_at: Time.current)
      processed = 0
      failed = 0
      errors = []

      each_row do |row, index|
        begin
          attrs, tags = attributes_from_row(row)
          transaction = @user.transactions.build(attrs.merge(import_batch: @batch))
          transaction.acted_by = @user
          transaction.save!
          assign_tags(transaction, tags)
          processed += 1
        rescue StandardError => e
          failed += 1
          errors << "Row #{index + 1}: #{e.message}"
        end
      end

      finalize_batch(processed:, failed:, errors:)
    rescue StandardError => e
      finalize_batch(processed: 0, failed: 1, errors: [ e.message ], status: :failed)
      raise
    end

    private

    def each_row
      csv_options = { headers: @template.header?, col_sep: @template.delimiter.presence || "," }
      @batch.csv_file.open(tmpdir: Dir.tmpdir) do |file|
        CSV.foreach(file.path, **csv_options).with_index do |row, index|
          cells = row.is_a?(CSV::Row) ? row.to_h.values : Array(row)
          next if cells.all?(&:blank?)

          yield row, index
        end
      end
    end

    def attributes_from_row(row)
      attrs = { entry_type: :expense, status: :pending, occurred_on: Date.current }
      tags = []

      @template.mapping.each do |column, attribute|
        value = value_from(row, column)
        next if value.blank?

        case attribute
        when "account_name"
          attrs[:account] = find_account(value)
        when "amount"
          attrs[:amount] = parse_amount(value)
          attrs[:entry_type] = attrs[:amount].positive? ? :income : :expense
          attrs[:amount] = attrs[:amount].abs
        when "entry_type"
          attrs[:entry_type] = normalize_entry_type(value)
        when "occurred_on"
          attrs[:occurred_on] = Date.parse(value)
        when "memo"
          attrs[:memo] = value
        when "notes"
          attrs[:notes] = value
        when "tag_list"
          tags.concat(value.split(/[,;]/).map(&:strip))
        when "status"
          attrs[:status] = normalize_status(value)
        end
      end

      attrs[:account] ||= default_account
      attrs[:amount] ||= 0
      attrs[:occurred_on] ||= Date.current

      [ attrs, tags.uniq ]
    end

    def parse_amount(value)
      BigDecimal(value.gsub(/[^0-9\-\.]/, ""))
    rescue ArgumentError
      raise "Invalid amount: #{value}"
    end

    def normalize_entry_type(value)
      value.to_s.downcase.include?("income") ? :income : :expense
    end

    def normalize_status(value)
      value = value.to_s.downcase
      return value if Transaction.statuses.key?(value)

      value.include?("clear") ? "cleared" : "pending"
    end

    def assign_tags(transaction, tag_names)
      tags = tag_names.reject(&:blank?).map do |name|
        @user.tags.find_or_create_by!(name: name, slug: name.parameterize)
      end
      transaction.tags = tags if tags.present?
    end

    def find_account(name)
      @user.accounts.find_or_create_by!(name: name) do |account|
        account.account_type = :checking
      end
    end

    def default_account
      @default_account ||= @user.accounts.first || @user.accounts.create!(name: "General", account_type: :checking)
    end

    def value_from(row, column_key)
      if @template.header?
        row[column_key]&.to_s&.strip
      else
        index = column_key.to_i
        return nil if index <= 0
        cells = row.is_a?(CSV::Row) ? row.fields : row
        cells[index - 1]&.to_s&.strip
      end
    end

    def finalize_batch(processed:, failed:, errors:, status: nil)
      new_status = status || (failed.positive? ? :failed : :completed)
      @batch.update!(
        status: new_status,
        processed_count: processed,
        failed_count: failed,
        finished_at: Time.current,
        notes: errors.join("\n")
      )
    end
  end
end
