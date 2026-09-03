# frozen_string_literal: true

# One uploaded CSV, kept.
#
# The personal VISA could not be repaired in place because its source files were
# gone and no CSV was ever retained. Holding on to the file is what makes a
# future repair possible at all. See docs/adr/0002.
class CsvImport < ApplicationRecord
  belongs_to :account
  belongs_to :user

  # The rows this file produced. They outlive the import record if it is ever
  # removed — provenance is a convenience, not the transaction's identity.
  has_many :transactions, dependent: :nullify

  has_one_attached :file

  validates :filename, :digest, presence: true

  scope :newest_first, -> { order(created_at: :desc) }

  def self.digest_for(content) = Digest::SHA256.hexdigest(content)

  def short_digest = digest.first(12)
end
