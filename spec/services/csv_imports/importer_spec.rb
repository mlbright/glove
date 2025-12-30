# frozen_string_literal: true

require "rails_helper"

RSpec.describe CsvImports::Importer do
  let(:user) { create(:user) }
  let(:account) { create(:account, name: "TD Chequing") }

  describe "#import with td_chequing format" do
    it "imports transactions from CSV" do
      csv_content = <<~CSV
        "2025-11-14","ACME Corp  PAY",,"1000.00","1500.00"
        "2025-11-17","UX215 TFR-TO C1234567","800.00",,"700.00"
      CSV

      importer = described_class.new(user: user, account: account, format: :td_chequing)
      result = importer.import(csv_content)

      # 3 transactions: opening balance + 2 imported
      expect(result.imported_count).to eq 3
      expect(result.error_count).to eq 0

      transactions = account.transactions.order(:occurred_on, :id)
      expect(transactions.count).to eq 3

      # Opening balance transaction (calculated from first row: 1500.00 - 1000.00 = 500.00)
      expect(transactions.first.description).to eq "Opening Balance"
      expect(transactions.first.amount).to eq Money.new(50000, :cad)
      expect(transactions.first.entry_type).to eq "income"

      # First CSV transaction - credit (income)
      expect(transactions.second.occurred_on.to_date).to eq Date.new(2025, 11, 14)
      expect(transactions.second.description).to eq "ACME Corp  PAY"
      expect(transactions.second.amount).to eq Money.new(100000, :cad)
      expect(transactions.second.entry_type).to eq "income"
      expect(transactions.second.status).to eq "cleared"

      # Second CSV transaction - debit (expense)
      expect(transactions.third.occurred_on.to_date).to eq Date.new(2025, 11, 17)
      expect(transactions.third.description).to eq "UX215 TFR-TO C1234567"
      expect(transactions.third.amount).to eq Money.new(80000, :cad)
      expect(transactions.third.entry_type).to eq "expense"
    end

    it "skips duplicate transactions" do
      # Create an existing transaction
      create(:transaction,
        account: account,
        occurred_on: Time.new(2025, 11, 14),
        description: "ACME Corp  PAY",
        amount: 1000.00,
        entry_type: :income
      )

      csv_content = <<~CSV
        "2025-11-14","ACME Corp  PAY",,"1000.00","1500.00"
        "2025-11-17","UX215 TFR-TO C1234567","800.00",,"700.00"
      CSV

      importer = described_class.new(user: user, account: account, format: :td_chequing)
      result = importer.import(csv_content)

      expect(result.imported_count).to eq 1
      expect(result.skipped_count).to eq 1
      expect(account.transactions.count).to eq 2
    end
  end

  describe "#import with td_visa format" do
    let(:account) { create(:account, name: "TD Visa") }

    it "imports transactions from CSV" do
      csv_content = <<~CSV
        11/24/2025,BALANCE PROTECTION INS,20.67,,2109.88
        11/23/2025,TIM HORTONS #0788,3.70,,1924.29
      CSV

      importer = described_class.new(user: user, account: account, format: :td_visa)
      result = importer.import(csv_content)

      # 3 transactions: opening balance + 2 imported
      expect(result.imported_count).to eq 3
      expect(result.error_count).to eq 0

      transactions = account.transactions.order(:occurred_on, :id)
      expect(transactions.count).to eq 3

      # Opening balance (from earliest row: 1924.29 - 3.70 = 1920.59)
      expect(transactions.first.description).to eq "Opening Balance"

      # Both CSV transactions should be expenses
      expect(transactions.second.entry_type).to eq "expense"
      expect(transactions.third.entry_type).to eq "expense"
    end
  end

  describe "#import with mastercard format" do
    let(:account) { create(:account, name: "Mastercard") }

    it "imports transactions from CSV" do
      csv_content = <<~CSV
        "Description","Type","Card Holder Name","Date","Time","Amount"
        "TIM HORTONS #1723","PURCHASE","JOHN DOE","12/11/2025","01:35 AM","-1.92"
        "LOBLAWS MAIN ST","PURCHASE","JOHN DOE","12/11/2025","01:25 AM","-79.05"
      CSV

      importer = described_class.new(user: user, account: account, format: :mastercard)
      result = importer.import(csv_content)

      expect(result.imported_count).to eq 2
      expect(result.error_count).to eq 0

      transactions = account.transactions.order(:amount_cents)
      expect(transactions.count).to eq 2

      # Both should be expenses (purchases)
      expect(transactions.first.entry_type).to eq "expense"
      expect(transactions.first.amount).to eq Money.new(192, :cad)
      expect(transactions.first.description).to eq "TIM HORTONS #1723"

      expect(transactions.second.entry_type).to eq "expense"
      expect(transactions.second.amount).to eq Money.new(7905, :cad)
    end
  end

  describe "#import with unknown format" do
    it "raises an error" do
      importer = described_class.new(user: user, account: account, format: :unknown)

      expect { importer.import("data") }.to raise_error(ArgumentError, /Unknown format/)
    end
  end
end
