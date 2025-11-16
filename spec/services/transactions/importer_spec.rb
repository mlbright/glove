require "rails_helper"

RSpec.describe Transactions::Importer do
  let(:user) { create(:user) }
  let!(:account) { create(:account, user: user, name: "Checking") }
  let(:template) do
    create(:import_template, user: user, mapping: {
      "Account" => "account_name",
      "Amount" => "amount",
      "Type" => "entry_type",
      "Date" => "occurred_on",
      "Tags" => "tag_list"
    })
  end
  let(:batch) { create(:import_batch, user: user, import_template: template) }

  it "imports rows into transactions" do
    batch.csv_file.attach(io: StringIO.new("Account,Amount,Type,Date,Tags\nChecking,120,Income,2025-01-01,Salary"), filename: "rows.csv", content_type: "text/csv")

    expect { described_class.new(batch).call }.to change(Transaction, :count).by(1)
    transaction = Transaction.last
    expect(transaction.amount).to eq(120)
    expect(transaction.tags.first.name).to eq("Salary")
    expect(batch.reload.status).to eq("completed")
  end
end
