# frozen_string_literal: true

module Transactions
  # Removes rows that the bank's own balance column proves cannot exist.
  #
  # Two rows sharing a date, description, amount and entry type *and* the
  # balance printed against them cannot both be genuine: a balance is the
  # account after a row, so two distinct events with a non-zero amount cannot
  # leave it in the same state.
  #
  # This uses the column in the only direction it can bear. It may merge two
  # rows and never split them: a differing balance is no evidence that two rows
  # are distinct, because a re-import prints a different running balance against
  # the same purchase, which is exactly how the rows this removes were created.
  # ADR 2's rejection of balance as part of the matching key is untouched.
  # See docs/adr/0003.
  class BalanceCollapse
    # A group the rule can adjudicate: one row kept, the rest provably spurious.
    Group = Data.define(:occurred_on, :description, :amount_cents, :entry_type,
                        :balance_cents, :keep_id, :discard_ids) do
      def discarded_count = discard_ids.size

      # Removing an expense raises the balance; removing income lowers it.
      def ledger_change_cents
        (entry_type.to_s == "income" ? -amount_cents : amount_cents) * discarded_count
      end

      def label = "#{occurred_on} #{description}"
    end

    Result = Data.define(:groups) do
      def any? = groups.any?
      def removed_count = groups.sum(&:discarded_count)
      def ledger_change_cents = groups.sum(&:ledger_change_cents)
    end

    class UnsupportedFormat < StandardError; end

    def initialize(account)
      @account = account
    end

    # What the rule would remove. Nothing is written; a mismatch is reported and
    # never repaired without an instruction, as ADR 2 requires.
    def plan
      Result.new(groups: collapsible_groups)
    end

    def apply!(acted_by: nil)
      result = plan

      Transaction.transaction do
        result.groups.each do |group|
          @account.transactions.where(id: group.discard_ids).find_each do |transaction|
            # Recorded through Revisable, so a removal is reconstructible from
            # the audit trail rather than simply gone.
            transaction.acted_by = acted_by
            transaction.destroy!
          end
        end
      end

      result
    end

    private

    def collapsible_groups
      eligible_rows
        .group_by { |t| [ t.occurred_on.to_date, t.description, t.amount_cents, t.entry_type, t.balance_cents ] }
        .filter_map { |key, members| build_group(key, members) if members.size > 1 }
        .sort_by { |group| [ group.occurred_on, group.description.to_s ] }
    end

    # Only rows the argument covers. A row with no printed balance carries no
    # such assertion, and a zero amount would let two genuine rows share one
    # balance honestly — the model forbids those, but the rule does not rely on
    # that holding forever.
    def eligible_rows
      raise UnsupportedFormat, "#{@account.name} has no balance column to reason from" unless balance_bearing?

      @account.transactions.where.not(balance_cents: nil).where.not(amount_cents: 0).order(:id).to_a
    end

    def balance_bearing?
      CsvImports::Format.find(@account.import_format)&.reconciles_balance?
    end

    # The earliest row is the one the account already held; later insertions of
    # the same row are what re-importing produced.
    def build_group(key, members)
      Group.new(
        occurred_on: key[0], description: key[1], amount_cents: key[2],
        entry_type: key[3], balance_cents: key[4],
        keep_id: members.first.id, discard_ids: members.drop(1).map(&:id)
      )
    end
  end
end
