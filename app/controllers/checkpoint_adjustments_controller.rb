# frozen_string_literal: true

# Closes the gap in the interval ending at a checkpoint with an ordinary,
# clearly labelled transaction.
#
# A mismatch is reported and never repaired silently: this only ever runs on an
# explicit instruction, and what it creates is a visible row that can be deleted
# when the real cause is found. See docs/adr/0002.
class CheckpointAdjustmentsController < ApplicationController
  def create
    checkpoint = Checkpoint.find(params[:checkpoint_id])
    account = checkpoint.account
    interval = Checkpoints::Audit.new(account).interval_ending_at(checkpoint)

    if interval.nil?
      return redirect_to account, alert: "That checkpoint is the earliest one on #{account.name}: there is no preceding checkpoint to measure it against, so there is no interval to adjust."
    end

    if interval.balanced?
      return redirect_to account, alert: "The interval #{interval.label} already balances. Nothing to adjust."
    end

    adjustment = build_adjustment(account, checkpoint, interval)

    if adjustment.save
      redirect_to account, notice: "Recorded a #{adjustment.amount.format} balance adjustment on #{checkpoint.closed_on}, closing the gap in #{interval.label}. It is an ordinary transaction: delete it once the real cause is found."
    else
      redirect_to account, alert: "Could not record the adjustment: #{adjustment.errors.full_messages.join(', ')}"
    end
  end

  private

  def build_adjustment(account, checkpoint, interval)
    difference = interval.discrepancy_cents

    adjustment = account.transactions.build(
      # Dated inside the interval it closes, on its closing day.
      occurred_on: checkpoint.closed_on.beginning_of_day,
      amount_cents: difference.abs,
      # The account closed higher than its transactions explain, so money is
      # missing; the other way round, something has been counted twice.
      entry_type: difference.positive? ? :income : :expense,
      description: Transaction::ADJUSTMENT_DESCRIPTION,
      notes: "Closes the gap between the checkpoints of #{interval.label}, where #{interval.transaction_count} transactions reach #{Money.new(interval.expected_cents, :cad).format} against a checkpoint of #{Money.new(interval.actual_cents, :cad).format}.",
      status: :cleared,
      adjusted_checkpoint: checkpoint
    )
    adjustment.acted_by = current_user
    adjustment
  end
end
