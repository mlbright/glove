require "rails_helper"

RSpec.describe "Transactions", type: :request do
  let(:user) { create(:user) }
  let!(:account) { create(:account, user: user) }

  before { sign_in user }

  it "creates a transaction" do
    post transactions_path, params: {
      transaction: {
        account_id: account.id,
        entry_type: :income,
        status: :cleared,
        amount: 50,
        occurred_on: Date.current,
        memo: "Invoice",
        tag_list: "Client"
      }
    }

    expect(response).to redirect_to(Transaction.last)
    expect(Transaction.count).to eq(1)
    expect(Transaction.last.tags.first.name).to eq("Client")
  end
end
