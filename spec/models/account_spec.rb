require "rails_helper"

RSpec.describe Account, type: :model do
  it "calculates balance using income and expenses" do
    account = create(:account)
    create(:transaction, account: account, entry_type: :income, amount: 100)
    create(:transaction, account: account, entry_type: :expense, amount: 40)

    expect(account.balance).to eq(Money.new(6000, :cad))
  end
end
