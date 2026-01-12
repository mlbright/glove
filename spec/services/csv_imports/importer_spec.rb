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

    it "skips duplicate transactions and reconciles balance" do
      # Create an existing transaction (without balance_cents like a legacy entry)
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

      # First row is duplicate (skipped), second row is imported
      # Plus a Balance Adjustment to reconcile account balance ($1000) with CSV expected ($500 opening)
      expect(result.skipped_count).to eq 1
      expect(result.imported_count).to eq 2 # Second row + Balance Adjustment
      expect(result.warnings.count).to eq 1 # Balance mismatch warning
      expect(account.transactions.count).to eq 3 # Original + imported + adjustment
      expect(account.transactions.find_by(description: "Balance Adjustment")).to be_present
    end

    it "skips duplicates when re-importing the same CSV" do
      csv_content = <<~CSV
        "2025-11-14","ACME Corp  PAY",,"1000.00","1500.00"
        "2025-11-17","UX215 TFR-TO C1234567","800.00",,"700.00"
      CSV

      # First import
      importer1 = described_class.new(user: user, account: account, format: :td_chequing)
      result1 = importer1.import(csv_content)

      expect(result1.imported_count).to eq 3 # Opening balance + 2 transactions
      expect(account.transactions.count).to eq 3

      # Second import should skip all CSV rows as duplicates
      importer2 = described_class.new(user: user, account: account, format: :td_chequing)
      result2 = importer2.import(csv_content)

      expect(result2.imported_count).to eq 0
      expect(result2.skipped_count).to eq 2
      expect(account.transactions.count).to eq 3
    end

    it "skips duplicate rows within the same CSV file" do
      # Two identical rows (same balance_cents) should result in one being skipped
      csv_content = <<~CSV
        "2025-11-14","ACME Corp  PAY",,"1000.00","1500.00"
        "2025-11-14","ACME Corp  PAY",,"1000.00","1500.00"
      CSV

      importer = described_class.new(user: user, account: account, format: :td_chequing)
      result = importer.import(csv_content)

      expect(result.imported_count).to eq 2 # Opening balance + 1 transaction
      expect(result.skipped_count).to eq 1
      expect(account.transactions.where(description: "ACME Corp  PAY").count).to eq 1
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

    it "skips duplicates when re-importing the same CSV" do
      csv_content = <<~CSV
        "Description","Type","Card Holder Name","Date","Time","Amount"
        "TIM HORTONS #1723","PURCHASE","JOHN DOE","12/11/2025","01:35 AM","-1.92"
      CSV

      # First import
      importer1 = described_class.new(user: user, account: account, format: :mastercard)
      result1 = importer1.import(csv_content)

      expect(result1.imported_count).to eq 1
      expect(account.transactions.count).to eq 1

      # Second import of same data should skip all as duplicates
      importer2 = described_class.new(user: user, account: account, format: :mastercard)
      result2 = importer2.import(csv_content)

      expect(result2.imported_count).to eq 0
      expect(result2.skipped_count).to eq 1
      expect(result2.skipped_duplicates.first.description).to eq "TIM HORTONS #1723"
      expect(account.transactions.count).to eq 1
    end

    it "skips duplicate rows within the same CSV file" do
      csv_content = <<~CSV
        "Description","Type","Card Holder Name","Date","Time","Amount"
        "TIM HORTONS #1723","PURCHASE","JOHN DOE","12/11/2025","01:35 AM","-1.92"
        "TIM HORTONS #1723","PURCHASE","JOHN DOE","12/11/2025","01:35 AM","-1.92"
      CSV

      importer = described_class.new(user: user, account: account, format: :mastercard)
      result = importer.import(csv_content)

      # Should only import one, skip the duplicate
      # (skipped_count includes opening balance skip + duplicate row)
      expect(result.imported_count).to eq 1
      expect(result.skipped_duplicates.count).to eq 1
      expect(account.transactions.count).to eq 1
    end
  end

  describe "#import with unknown format" do
    it "raises an error" do
      importer = described_class.new(user: user, account: account, format: :unknown)

      expect { importer.import("data") }.to raise_error(ArgumentError, /Unknown format/)
    end
  end

  describe "balance reconciliation" do
    describe "with td_chequing format" do
      it "stores balance_cents on imported transactions" do
        csv_content = <<~CSV
          "2025-11-14","ACME Corp  PAY",,"1000.00","1500.00"
          "2025-11-17","UX215 TFR-TO C1234567","800.00",,"700.00"
        CSV

        importer = described_class.new(user: user, account: account, format: :td_chequing)
        importer.import(csv_content)

        transactions = account.transactions.where.not(description: "Opening Balance").order(:occurred_on)
        expect(transactions.first.balance_cents).to eq 150_000
        expect(transactions.second.balance_cents).to eq 70_000
      end

      it "detects balance mismatch and creates Balance Adjustment transaction" do
        # Create an existing transaction that throws off the balance
        create(:transaction,
          account: account,
          occurred_on: Time.new(2025, 11, 10),
          description: "Previous transaction",
          amount: 200.00,
          entry_type: :income
        )

        csv_content = <<~CSV
          "2025-11-14","ACME Corp  PAY",,"1000.00","1500.00"
        CSV

        importer = described_class.new(user: user, account: account, format: :td_chequing)
        result = importer.import(csv_content)

        expect(result.warnings.count).to eq 1
        expect(result.warnings.first.message).to include("Balance mismatch detected")

        # Should have created a Balance Adjustment transaction
        adjustment = account.transactions.find_by(description: "Balance Adjustment")
        expect(adjustment).to be_present
      end

      it "uses balance_cents for enhanced duplicate detection" do
        # Create an existing transaction with matching attributes but different balance
        create(:transaction,
          account: account,
          occurred_on: Time.new(2025, 11, 14),
          description: "ACME Corp  PAY",
          amount: 1000.00,
          entry_type: :income,
          balance_cents: 150_000
        )

        csv_content = <<~CSV
          "2025-11-14","ACME Corp  PAY",,"1000.00","1500.00"
        CSV

        importer = described_class.new(user: user, account: account, format: :td_chequing)
        result = importer.import(csv_content)

        # Should be skipped as duplicate (same balance_cents)
        expect(result.skipped_count).to eq 1
        expect(account.transactions.count).to eq 1
      end

      it "imports transaction when balance_cents differs from existing" do
        # Create an existing transaction with same date/amount/description but different balance
        # This represents a legitimate separate transaction
        create(:transaction,
          account: account,
          occurred_on: Time.new(2025, 11, 14),
          description: "ACME Corp  PAY",
          amount: 1000.00,
          entry_type: :income,
          balance_cents: 50_000 # Different balance
        )

        csv_content = <<~CSV
          "2025-11-14","ACME Corp  PAY",,"1000.00","1500.00"
        CSV

        importer = described_class.new(user: user, account: account, format: :td_chequing)
        result = importer.import(csv_content)

        # Should import as new transaction (different balance_cents)
        expect(result.imported_count).to be >= 1
        expect(account.transactions.where(description: "ACME Corp  PAY").count).to eq 2
      end

      it "replays newer existing transactions to update balance_cents" do
        # Import initial transactions
        csv_content_initial = <<~CSV
          "2025-11-14","ACME Corp  PAY",,"1000.00","1500.00"
        CSV

        importer = described_class.new(user: user, account: account, format: :td_chequing)
        importer.import(csv_content_initial)

        # Add a manual transaction after the import
        manual_tx = create(:transaction,
          account: account,
          occurred_on: Time.new(2025, 11, 20),
          description: "Manual entry",
          amount: 100.00,
          entry_type: :expense,
          balance_cents: nil
        )

        # Import more transactions that include older dates
        csv_content_new = <<~CSV
          "2025-11-14","ACME Corp  PAY",,"1000.00","1500.00"
          "2025-11-17","UX215 TFR-TO C1234567","800.00",,"700.00"
        CSV

        importer2 = described_class.new(user: user, account: account, format: :td_chequing)
        importer2.import(csv_content_new)

        # The manual transaction should have its balance_cents updated
        manual_tx.reload
        expect(manual_tx.balance_cents).to eq 60_000 # 700.00 - 100.00 = 600.00
      end
    end

    describe "with td_visa format" do
      let(:account) { create(:account, name: "TD Visa") }

      it "stores balance_cents on imported transactions" do
        csv_content = <<~CSV
          11/24/2025,BALANCE PROTECTION INS,20.67,,2109.88
          11/23/2025,TIM HORTONS #0788,3.70,,1924.29
        CSV

        importer = described_class.new(user: user, account: account, format: :td_visa)
        importer.import(csv_content)

        transactions = account.transactions.where.not(description: "Opening Balance").order(:occurred_on)
        expect(transactions.first.balance_cents).to eq 192_429 # Earlier transaction
        expect(transactions.second.balance_cents).to eq 210_988 # Later transaction
      end

      it "detects balance mismatch and creates adjustment for credit card" do
        create(:transaction,
          account: account,
          occurred_on: Time.new(2025, 11, 20),
          description: "Existing charge",
          amount: 50.00,
          entry_type: :expense
        )

        csv_content = <<~CSV
          11/23/2025,TIM HORTONS #0788,3.70,,1924.29
        CSV

        importer = described_class.new(user: user, account: account, format: :td_visa)
        result = importer.import(csv_content)

        expect(result.warnings.count).to eq 1
        adjustment = account.transactions.find_by(description: "Balance Adjustment")
        expect(adjustment).to be_present
      end
    end

    describe "with mastercard format" do
      let(:account) { create(:account, name: "Mastercard") }

      it "skips balance reconciliation (no balance data)" do
        create(:transaction,
          account: account,
          occurred_on: Time.new(2025, 12, 1),
          description: "Existing",
          amount: 100.00,
          entry_type: :expense
        )

        csv_content = <<~CSV
          "Description","Type","Card Holder Name","Date","Time","Amount"
          "TIM HORTONS #1723","PURCHASE","JOHN DOE","12/11/2025","01:35 AM","-1.92"
        CSV

        importer = described_class.new(user: user, account: account, format: :mastercard)
        result = importer.import(csv_content)

        # Should NOT create balance adjustment or warnings for Mastercard
        expect(result.warnings).to be_empty
        expect(account.transactions.find_by(description: "Balance Adjustment")).to be_nil
      end
    end
  end
end
