# frozen_string_literal: true

# One recorded change to a revisable record — a transaction or a checkpoint.
#
# There is no foreign key on record_id: a destroy revision outlives the row it
# describes, which is the whole point of recording one.
class Revision < ApplicationRecord
  belongs_to :record, polymorphic: true
  belongs_to :user

  validates :action, :recorded_at, presence: true

  scope :newest_first, -> { order(recorded_at: :desc) }
end
