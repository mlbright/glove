class ImportBatch < ApplicationRecord
  belongs_to :user
  belongs_to :import_template

  has_one_attached :csv_file

  enum :status, { pending: 0, processing: 1, completed: 2, failed: 3 }

  validates :csv_file, presence: true
end
