require "rails_helper"

RSpec.describe Transaction, type: :model do
  let(:user) { create(:user) }
  let(:account) { create(:account, user: user) }

  it "validates presence of amount" do
    transaction = described_class.new(user: user, account: account, amount: nil, entry_type: :expense, occurred_on: Date.current)
    expect(transaction).to be_invalid
  end

  it "calculates amount_signed" do
    income = create(:transaction, user: user, account: account, entry_type: :income, amount: 10)
    expense = create(:transaction, user: user, account: account, entry_type: :expense, amount: 4)

    expect(income.amount_signed).to eq(10)
    expect(expense.amount_signed).to eq(-4)
  end

  it "records revisions on create" do
    transaction = build(:transaction, user: user, account: account)
    transaction.acted_by = user

    expect { transaction.save! }.to change(TransactionRevision, :count).by(1)
  end

  it "records revisions on update" do
    transaction = create(:transaction, user: user, account: account)
    transaction.acted_by = user

    expect { transaction.update!(memo: "Lunch") }.to change(TransactionRevision, :count).by(1)
  end
end
