require "rails_helper"

RSpec.describe Revision, type: :model do
  it "requires an action" do
    revision = build(:revision, action: nil)
    expect(revision).not_to be_valid
  end

  it "records revisions for any revisable record, not only transactions" do
    user = create(:user)
    checkpoint = create(:checkpoint, acted_by: user)

    expect(checkpoint.revisions.map(&:action)).to eq([ "create" ])
    expect(checkpoint.revisions.first.record).to eq(checkpoint)
  end

  it "orders newest first" do
    transaction = create(:transaction)
    transaction.update!(description: "Tea")

    expect(transaction.revisions.newest_first.map(&:action)).to eq(%w[update create])
  end
end
