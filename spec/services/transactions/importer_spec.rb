require "rails_helper"

RSpec.describe Transactions::Importer do
  let(:user) { create(:user) }
  let!(:account) { create(:account, user: user, name: "Checking") }

  context "with headers" do
    let(:template) do
      create(:import_template, user: user, header: true, mapping: {
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

  context "without headers" do
    let(:template) do
      create(:import_template, user: user, header: false, mapping: {
        "1" => "account_name",
        "2" => "amount",
        "3" => "entry_type",
        "4" => "occurred_on"
      })
    end
    let(:batch) { create(:import_batch, user: user, import_template: template) }

    it "maps by column number" do
      batch.csv_file.attach(io: StringIO.new("Checking,42.5,expense,2025-02-01"), filename: "rows.csv", content_type: "text/csv")

      expect { described_class.new(batch).call }.to change(Transaction, :count).by(1)
      transaction = Transaction.last
      expect(transaction.account).to eq(account)
      expect(transaction.amount).to eq(42.5)
      expect(transaction.expense?).to be(true)
      expect(batch.reload.status).to eq("completed")
    end
  end
end
