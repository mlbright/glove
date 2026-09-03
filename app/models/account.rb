class Account < ApplicationRecord
  has_many :transactions, dependent: :destroy
  has_many :checkpoints, dependent: :destroy
  has_many :csv_imports, dependent: :destroy

  # An account has exactly one import format, or none. The format is a property
  # of the account rather than a choice made at import time, so that picking an
  # account settles which parser its CSV gets. See docs/adr/0001.
  enum :import_format, CsvImports::Format.enum_mapping, validate: { allow_nil: true }

  validates :name, presence: true, uniqueness: true

  scope :active, -> { where(archived_at: nil) }

  # Only accounts with a format can receive a CSV import: without one there is
  # no way to know how to read the file.
  def importable? = import_format.present?

  def import_format_label = CsvImports::Format.label_for(import_format)

  # The balance anchors to the latest checkpoint: that assertion plus the
  # transactions dated strictly after it. Anything before the checkpoint stays
  # visible and searchable but does not contribute, because the checkpoint
  # already accounts for it. See docs/adr/0002.
  #
  # An account with no checkpoint falls back to summing every transaction. That
  # is the pre-checkpoint behaviour, and it is wrong in the ways ADR 2
  # describes — callers show a warning rather than the number alone.
  def balance
    Money.new(balance_cents, :cad)
  end

  def balance_cents
    checkpoint = latest_checkpoint
    countable = transactions.counting_toward_balance
    return countable.signed_cents if checkpoint.nil?

    checkpoint.balance_cents + countable.after_checkpoint(checkpoint).signed_cents
  end

  # max_by rather than an ordered query so a preloaded association is used as
  # loaded; the unique index on [account_id, closed_on] rules out ties.
  def latest_checkpoint = checkpoints.max_by(&:closed_on)

  def anchored? = checkpoints.any?
end
