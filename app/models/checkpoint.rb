# frozen_string_literal: true

# An assertion that on a given date the account closed at a given amount.
#
# An account's balance anchors to its latest checkpoint: the balance is that
# checkpoint plus the transactions dated strictly after it. Transactions before
# it stay visible and searchable but do not contribute. An opening balance is
# simply the earliest checkpoint and a monthly reconciliation is another; there
# is one concept, not two. See docs/adr/0002.
class Checkpoint < ApplicationRecord
  include Revisable

  # derived: computed by the importer from a bank's own balance column.
  # verified: entered, or corrected, by a person holding a statement.
  enum :source, { derived: 0, verified: 1 }

  belongs_to :account

  # An adjustment survives its checkpoint: deleting the checkpoint leaves an
  # ordinary visible row rather than quietly removing money from the ledger.
  has_many :adjustments,
           class_name: "Transaction",
           foreign_key: :adjusts_checkpoint_id,
           dependent: :nullify,
           inverse_of: :adjusted_checkpoint

  monetize :balance_cents

  validates :closed_on, presence: true, uniqueness: { scope: :account_id }
  validates :balance_cents, numericality: { only_integer: true }

  scope :chronological, -> { order(:closed_on) }

  # Correcting a derived checkpoint is precisely the act of verifying it: a
  # person only changes this number by holding it against a statement.
  before_update :promote_to_verified

  # Exclusive upper bound of what this checkpoint accounts for: everything
  # dated on or before its own day happened strictly before this instant, which
  # is what makes the number an end-of-day closing balance.
  def closes_before = (closed_on + 1).beginning_of_day

  def previous = account.checkpoints.where(closed_on: ...closed_on).chronological.last

  private

  def promote_to_verified
    return unless derived?
    return if source_changed?
    return unless balance_cents_changed? || closed_on_changed?

    self.source = :verified
  end
end
