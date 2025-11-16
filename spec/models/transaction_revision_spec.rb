require "rails_helper"

RSpec.describe TransactionRevision, type: :model do
  it "requires an action" do
    revision = build(:transaction_revision, action: nil)
    expect(revision).not_to be_valid
  end
end
