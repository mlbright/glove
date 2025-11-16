require "rails_helper"

RSpec.describe Schedule, type: :model do
  let(:schedule) { create(:schedule, frequency: :weekly, interval_value: 2, next_occurs_on: Date.new(2025, 1, 1)) }

  it "advances by interval when calling advance!" do
    schedule.advance!
    expect(schedule.next_occurs_on).to eq(Date.new(2025, 1, 15))
  end
end
