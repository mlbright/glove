class Schedule < ApplicationRecord
  belongs_to :user
  belongs_to :account, optional: true

  has_many :transactions, dependent: :nullify

  enum :frequency, { one_time: 0, daily: 1, weekly: 2, monthly: 3 }

  validates :name, :next_occurs_on, presence: true
  validates :interval_value, numericality: { greater_than: 0 }

  scope :active, -> { where(active: true) }
  scope :due_on_or_before, ->(date) { active.where("next_occurs_on <= ?", date) }

  def advance!
    self.next_occurs_on = case frequency.to_sym
                          when :daily then next_occurs_on + interval_value.days
                          when :weekly then next_occurs_on + interval_value.weeks
                          when :monthly then next_occurs_on.advance(months: interval_value)
                          else
                            next_occurs_on
                          end
    save!
  end
end
