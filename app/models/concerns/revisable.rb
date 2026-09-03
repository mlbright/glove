# frozen_string_literal: true

# Records every create, update and destroy of a record as a Revision.
#
# Extracted from Transaction when checkpoints gained an audit trail. A
# checkpoint deserves one at least as much as a transaction does: the balance
# hangs off its number, and ADR 1 was written about damage that surfaced later
# as a balance nobody could reconstruct. See docs/adr/0002.
module Revisable
  extend ActiveSupport::Concern

  included do
    # Who is making the change. Set by the controller or the importer; a record
    # saved without one leaves the revision unattributed rather than unwritten.
    attr_accessor :acted_by

    has_many :revisions, as: :record, dependent: nil, inverse_of: :record

    after_create_commit -> { record_revision("create") }
    after_update_commit -> { record_revision("update") }
    after_destroy_commit -> { record_revision("destroy") }
  end

  private

  def record_revision(action)
    Revision.create!(
      record: self,
      user: acted_by,
      action: action,
      change_log: change_log_for(action),
      recorded_at: Time.current
    )
  end

  def change_log_for(action)
    if action == "destroy"
      attributes
    else
      previous_changes.except(:updated_at, :created_at)
    end
  end
end
