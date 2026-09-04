# frozen_string_literal: true

module Transactions
  # Audits an account's rows against the running balance its bank printed
  # against each one.
  #
  # Between two consecutive balance-bearing rows the bank is stating an
  # equation: the balance moved by exactly the later row's signed amount. Where
  # the checkpoint audit of ADR 2 confines a discrepancy to the interval between
  # two statements, this confines it to the gap between two rows. Both run: this
  # one is far finer but exists only where the column does, and it structurally
  # cannot see a row missing from a file altogether. See docs/adr/0003.
  #
  # A violation is reported and never repaired. The chain proves that two
  # adjacent rows disagree, not which of them is wrong.
  class BalanceAudit
    Pair = Data.define(:earlier, :later, :expected_cents, :actual_cents) do
      # What the printed column moved by, against what the later row records.
      # Positive means the column moved further than the row explains.
      def residual_cents = actual_cents - expected_cents

      def balanced? = residual_cents.zero?

      def same_day? = earlier.occurred_on.to_date == later.occurred_on.to_date

      def numbered? = earlier.import_row_number.present? && later.import_row_number.present?

      # Rows dated days apart cannot be out of order. Rows sharing a date can:
      # TD stamps every row of a day at local midnight, and the historical rows
      # pass today because `id` happens to have been assigned in file order.
      # `import_row_number` turns that luck into a guarantee for anything
      # imported since. A violation resting on the assumption is weaker evidence
      # than one on rows a week apart and is reported as such.
      def order_assumed? = same_day? && !numbered?

      # The later row, which is a presentational convenience and not a claim
      # about which of the two is wrong.
      def label = "#{later.occurred_on.to_date} #{later.description}"
    end

    def initialize(account)
      @account = account
    end

    # False for a format carrying no balance column — the PC Financial
    # Mastercard — where there is nothing to audit against. Callers say so
    # rather than showing a pass, so that an audit that cannot run is not read
    # as one that ran and found nothing.
    def supported? = format&.reconciles_balance? || false

    def pairs = @pairs ||= supported? ? build_pairs : []

    def violations = pairs.reject(&:balanced?)

    def balanced? = violations.empty?

    def checked_count = pairs.size

    # Where the chain stops and picks up again: a row carrying no balance, and
    # the join between two files, whose rows are adjacent in the account but
    # were never adjacent in any statement.
    def suspension_count
      @suspension_count ||= supported? ? unsubstantiated_pairs + chains.size - 1 : 0
    end

    # These telescope: across an unbroken chain they collapse to the last
    # printed balance minus the ledger, which is an identity that holds for any
    # data at all. The total restates a gap rather than evidencing one. What
    # this audit contributes is the distribution, which no identity determines.
    def residual_cents = violations.sum(&:residual_cents)

    private

    def format = @format ||= CsvImports::Format.find(@account.import_format)

    def build_pairs
      chains.flat_map { |rows| rows.each_cons(2).filter_map { |earlier, later| build_pair(earlier, later) } }
    end

    # One chain per file. Rows imported before files were retained carry none
    # and form a single chain ordered by date and insertion.
    def chains
      @chains ||= transactions.group_by(&:csv_import_id)
                              .values
                              .map { |rows| rows.sort_by { |row| order_key(row) } }
    end

    def transactions = @transactions ||= @account.transactions.to_a

    # Chronological. A date alone does not settle it, so the file's own row
    # number breaks the tie, negated for an export that runs newest first. Rows
    # predating that column fall back to insertion order, which the importer
    # assigns chronologically.
    def order_key(row) = [ row.occurred_on, sequence(row), row.id ]

    def sequence(row)
      return 0 if row.import_row_number.nil?

      format.newest_first? ? -row.import_row_number : row.import_row_number
    end

    # A row with no printed balance suspends the chain rather than being audited
    # across: a hand-entered row moves the account without the bank having
    # recorded it, and reporting that as a violation would substantiate nothing.
    def build_pair(earlier, later)
      return nil if earlier.balance_cents.nil? || later.balance_cents.nil?

      Pair.new(
        earlier: earlier,
        later: later,
        expected_cents: later.amount_signed.cents,
        actual_cents: printed_movement(earlier, later)
      )
    end

    # A credit card prints its debt as a positive number, so both ends go
    # through the format's sign convention before they can be subtracted.
    def printed_movement(earlier, later)
      format.signed_balance_cents(later.balance_cents) - format.signed_balance_cents(earlier.balance_cents)
    end

    def unsubstantiated_pairs
      chains.sum do |rows|
        rows.each_cons(2).count { |earlier, later| earlier.balance_cents.nil? || later.balance_cents.nil? }
      end
    end
  end
end
