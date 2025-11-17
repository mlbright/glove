require "rails_helper"

RSpec.describe "Transactions", type: :request do
  let(:user) { create(:user) }
  let!(:account) { create(:account, user: user) }

  it "creates a transaction" do
    sign_in user, scope: :user
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

  it "destroys a transaction" do
    transaction = create(:transaction, user: user, account: account)
    sign_in user, scope: :user

    expect do
      delete transaction_path(transaction)
    end.to change(Transaction, :count).by(-1)

    expect(response).to redirect_to(transactions_path)
  end
end
