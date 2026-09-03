# frozen_string_literal: true

module Checkpoints
  # Validates an account's consecutive checkpoints against each other.
  #
  # When a checkpoint plus the transactions following it does not reach the next
  # checkpoint, the difference is contained within that interval and is reported
  # that way. This is the part that earns the feature: it converts a balance
  # that is wrong by some amount somewhere across two years into a discrepancy
  # provably inside one month. See docs/adr/0002.
  class Audit
    Interval = Data.define(:opening, :closing, :expected_cents, :transaction_count, :adjustments) do
      def actual_cents = closing.balance_cents

      # Positive means the account closed higher than its transactions explain:
      # something is missing. Negative means something is counted twice.
      def discrepancy_cents = actual_cents - expected_cents

      def balanced? = discrepancy_cents.zero?

      def adjusted? = adjustments.any?

      # An adjustment closed this gap when it was made. If the interval no
      # longer balances, a checkpoint has been edited underneath it and the
      # adjustment is now the wrong amount. Flagged, never removed.
      def stale_adjustment? = adjusted? && !balanced?

      def label = "#{opening.closed_on} to #{closing.closed_on}"
    end

    def initialize(account)
      @account = account
    end

    def intervals
      @intervals ||= checkpoints.each_cons(2).map { |opening, closing| build_interval(opening, closing) }
    end

    def discrepancies = intervals.reject(&:balanced?)

    def stale_adjustments = intervals.select(&:stale_adjustment?)

    def balanced? = discrepancies.empty?

    # The interval a gap would be closed in if this checkpoint were adjusted:
    # the one ending at it. Nil for the earliest checkpoint, which has nothing
    # before it to be measured against.
    def interval_ending_at(checkpoint)
      intervals.find { |interval| interval.closing.id == checkpoint.id }
    end

    private

    def checkpoints = @checkpoints ||= @account.checkpoints.chronological.to_a

    def build_interval(opening, closing)
      scope = @account.transactions
                      .counting_toward_balance
                      .after_checkpoint(opening)
                      .through_checkpoint(closing)

      Interval.new(
        opening: opening,
        closing: closing,
        expected_cents: opening.balance_cents + scope.signed_cents,
        transaction_count: scope.count,
        adjustments: @account.transactions.where(adjusts_checkpoint_id: closing.id).to_a
      )
    end
  end
end
