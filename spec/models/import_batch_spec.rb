require "rails_helper"

RSpec.describe ImportBatch, type: :model do
  it "requires a CSV file" do
    batch = build(:import_batch)
    expect(batch).to be_valid

    batch.csv_file.detach
    expect(batch).not_to be_valid
  end
end
