require "rails_helper"

RSpec.describe TransactionTag, type: :model do
  it "enforces unique tag per transaction" do
    tag = create(:tag)
    account = create(:account)
    transaction = build(:transaction, account: account)
    transaction.acted_by = tag.user
    transaction.save!
    create(:transaction_tag, tag: tag, transaction_record: transaction)

    duplicate = build(:transaction_tag, tag: tag, transaction_record: transaction)
    expect(duplicate).not_to be_valid
  end
end
