# frozen_string_literal: true

module CsvImports
  # Decides which of a file's rows the account does not already hold.
  #
  # Rows are matched by occurrence within their group: for a given date, amount,
  # description and entry type, a file holding N such rows and a database
  # holding M of them contributes the occurrences after the Mth. Two coffees on
  # one day import as two; a re-imported overlapping period imports nothing.
  #
  # No export we read carries a transaction id, so identity has to be inferred
  # from content. The file's digest and row number are recorded as provenance
  # and are deliberately not part of the key: statement exports overlap, the
  # same purchase sits at different offsets in the March and April files, and
  # identity by position would duplicate every overlap wholesale. See
  # docs/adr/0002.
  class RowMatcher
    def initialize(account)
      @unclaimed = existing_occurrences(account)
    end

    # Consumes one already-held occurrence per call, so asking about the same
    # group repeatedly walks through the account's copies before reporting the
    # rest as new. Call once per row, in file order.
    def new_occurrence?(row)
      key = key_for(row.occurred_at, row.amount_cents, row.description, row.entry_type)
      return true if @unclaimed[key].zero?

      @unclaimed[key] -= 1
      false
    end

    private

    def existing_occurrences(account)
      counts = Hash.new(0)
      account.transactions
             .pluck(:occurred_on, :amount_cents, :description, :entry_type)
             .each do |occurred_on, amount_cents, description, entry_type|
        counts[key_for(occurred_on, amount_cents, description, entry_type)] += 1
      end
      counts
    end

    def key_for(occurred_at, amount_cents, description, entry_type)
      [ occurred_at.in_time_zone.to_date, amount_cents, description.to_s, entry_type_label(entry_type) ]
    end

    # Rows carry a symbol and the database an enum; pluck's casting of an enum
    # column is the kind of thing that changes between Rails versions, so accept
    # either shape rather than trusting one.
    def entry_type_label(value)
      value.is_a?(Integer) ? Transaction.entry_types.key(value) : value.to_s
    end
  end
end
