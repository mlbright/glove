class ImportTemplate < ApplicationRecord
  SUPPORTED_FIELDS = %w[account_name entry_type amount occurred_on memo notes tag_list status].freeze

  belongs_to :user

  has_many :import_batches, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :mapping, presence: true

  def attribute_for_column(column_name)
    mapping[column_name]
  end

  def sample_columns
    column_examples || []
  end
end
