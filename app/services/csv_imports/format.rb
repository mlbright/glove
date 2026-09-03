# frozen_string_literal: true

module CsvImports
  # The catalogue of CSV shapes Glove knows how to import: one entry per bank export.
  #
  # This is the single source of truth for the closed set of import formats. The
  # Account enum, the account form, the import form's reference block, and the
  # Importer all read from here, so teaching Glove a new bank is one edit.
  class Format
    Definition = Data.define(:key, :label, :parser, :reconciles_balance, :balance_is_debt, :columns, :example) do
      def reconciles_balance? = reconciles_balance

      # Whether the format's balance column counts what is owed rather than
      # what is held. A credit card's statement prints its debt as a positive
      # number; Glove reports debt as a negative balance, so the two disagree
      # about sign and only this flag knows it.
      def balance_is_debt? = balance_is_debt

      # The balance column as Glove signs balances: funds positive, debt negative.
      def signed_balance_cents(cents) = balance_is_debt? ? -cents : cents

      def to_s = key
    end

    ALL = [
      Definition.new(
        key: "td_chequing",
        label: "TD Chequing Account",
        parser: "CsvImports::TdChequingParser",
        reconciles_balance: true,
        balance_is_debt: false,
        columns: "Date (YYYY-MM-DD), Description, Debit, Credit, Balance",
        example: '"2025-11-14","ACME Corp  PAY",,"1000.00","1500.00"'
      ),
      Definition.new(
        key: "td_visa",
        label: "TD Visa Credit Card",
        parser: "CsvImports::TdVisaParser",
        reconciles_balance: true,
        balance_is_debt: true,
        columns: "Date (MM/DD/YYYY), Description, Debit, Credit, Balance",
        example: "11/24/2025,BALANCE PROTECTION INS,20.67,,2109.88"
      ),
      Definition.new(
        key: "mastercard",
        label: "PC Financial Mastercard",
        parser: "CsvImports::MastercardParser",
        reconciles_balance: false,
        balance_is_debt: true,
        columns: "Header row, then Description, Type, Card Holder Name, Date (MM/DD/YYYY), Time, Amount",
        example: '"TIM HORTONS #1723","PURCHASE","JOHN","12/11/2025","01:35 AM","-1.92"'
      )
    ].freeze

    class << self
      def all = ALL

      def keys = ALL.map(&:key)

      def find(key)
        return nil if key.blank?

        ALL.find { |format| format.key == key.to_s }
      end

      def fetch(key)
        find(key) || raise(ArgumentError, "Unknown import format: #{key.inspect}")
      end

      def label_for(key) = find(key)&.label

      # Parser classes are named rather than referenced so that the registry can
      # be loaded without eagerly pulling in every parser.
      def parser_for(key) = fetch(key).parser.constantize

      # Shape the Account enum expects: string values stored verbatim.
      def enum_mapping = keys.index_with { |key| key }

      # Shape a Rails select helper expects: [label, value] pairs.
      def options_for_select = ALL.map { |format| [ format.label, format.key ] }
    end
  end
end
