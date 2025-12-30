require "rails_helper"

RSpec.describe Transaction, type: :model do
  let(:user) { create(:user) }
  let(:account) { create(:account) }

  it "validates presence of amount" do
    transaction = described_class.new(account: account, amount: nil, entry_type: :expense, occurred_on: Time.current)
    expect(transaction).to be_invalid
  end

  it "calculates amount_signed" do
    income = create(:transaction, account: account, entry_type: :income, amount: 10)
    expense = create(:transaction, account: account, entry_type: :expense, amount: 4)

    expect(income.amount_signed).to eq(Money.new(1000, :cad))
    expect(expense.amount_signed).to eq(Money.new(-400, :cad))
  end

  it "records revisions on create" do
    transaction = build(:transaction, account: account)
    transaction.acted_by = user

    expect { transaction.save! }.to change(TransactionRevision, :count).by(1)
  end

  it "records revisions on update" do
    transaction = build(:transaction, account: account)
    transaction.acted_by = user
    transaction.save!

    expect { transaction.update!(description: "Lunch") }.to change(TransactionRevision, :count).by(1)
  end
end
