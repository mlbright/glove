# frozen_string_literal: true

require "rails_helper"

RSpec.describe CsvImports::Importer do
  let(:user) { create(:user) }
  let(:account) { create(:account, name: "TD Chequing") }

  def import(content, format:, into: account, csv_import: nil)
    described_class.new(user: user, account: into, import_format: format, csv_import: csv_import)
                   .import(content)
  end

  describe "#import with td_chequing format" do
    let(:csv_content) do
      <<~CSV
        "2025-11-14","ACME Corp  PAY",,"1000.00","1500.00"
        "2025-11-17","UX215 TFR-TO C1234567","800.00",,"700.00"
      CSV
    end

    it "imports one transaction per row and no synthetic opening balance" do
      result = import(csv_content, format: :td_chequing)

      expect(result.imported_count).to eq 2
      expect(result.error_count).to eq 0
      expect(account.transactions.where(description: "Opening Balance")).to be_empty

      transactions = account.transactions.order(:occurred_on, :id)
      expect(transactions.first.occurred_on.to_date).to eq Date.new(2025, 11, 14)
      expect(transactions.first.description).to eq "ACME Corp  PAY"
      expect(transactions.first.amount).to eq Money.new(100_000, :cad)
      expect(transactions.first.entry_type).to eq "income"
      expect(transactions.first.status).to eq "cleared"

      expect(transactions.second.occurred_on.to_date).to eq Date.new(2025, 11, 17)
      expect(transactions.second.amount).to eq Money.new(80_000, :cad)
      expect(transactions.second.entry_type).to eq "expense"
    end

    it "keeps the balance the bank printed against each row" do
      import(csv_content, format: :td_chequing)

      transactions = account.transactions.order(:occurred_on)
      expect(transactions.first.balance_cents).to eq 150_000
      expect(transactions.second.balance_cents).to eq 70_000
    end

    it "never rewrites the balance a row already carries" do
      import(csv_content, format: :td_chequing)
      manual = create(:transaction, account: account, occurred_on: Time.zone.parse("2025-11-20 12:00"),
                                    description: "Manual entry", amount: 100.00, entry_type: :expense,
                                    balance_cents: nil)

      import(csv_content, format: :td_chequing)

      # That column records what the bank printed on a row. A row it never
      # printed has no balance, and replaying over it destroyed the only
      # independent number the file carried. See docs/adr/0002.
      expect(manual.reload.balance_cents).to be_nil
    end
  end

  describe "deriving the opening checkpoint" do
    let(:csv_content) do
      <<~CSV
        "2025-11-14","ACME Corp  PAY",,"1000.00","1500.00"
        "2025-11-17","UX215 TFR-TO C1234567","800.00",,"700.00"
      CSV
    end

    it "reads the balance standing before the earliest row off the bank's own column" do
      result = import(csv_content, format: :td_chequing)

      checkpoint = result.derived_checkpoint
      expect(checkpoint).to be_persisted
      expect(checkpoint.closed_on).to eq Date.new(2025, 11, 13)
      expect(checkpoint.balance_cents).to eq 500_00
      expect(checkpoint).to be_derived
      expect(account.reload.balance).to eq Money.new(700_00, :cad)
    end

    it "signs a credit card's balance as debt" do
      visa = create(:account, name: "TD Visa")
      content = <<~CSV
        11/24/2025,BALANCE PROTECTION INS,20.67,,2109.88
        11/23/2025,TIM HORTONS #0788,3.70,,1924.29
      CSV

      result = import(content, format: :td_visa, into: visa)

      # The card owed 1924.29 after a 3.70 charge, so it owed 1920.59 before it.
      expect(result.derived_checkpoint.balance_cents).to eq(-192_059)
      expect(result.derived_checkpoint.closed_on).to eq Date.new(2025, 11, 22)
      # Anchor plus the two charges dated after it: -1920.59 - 3.70 - 20.67.
      expect(visa.reload.balance).to eq Money.new(-194_496, :cad)
    end

    it "derives nothing for an account that already holds transactions" do
      # Deriving an anchor for an account with history is exactly how the old
      # opening balance came to contradict the rows behind it.
      create(:transaction, account: account, occurred_on: Time.zone.parse("2025-10-01 12:00"))

      result = import(csv_content, format: :td_chequing)

      expect(result.derived_checkpoint).to be_nil
      expect(account.checkpoints).to be_empty
    end

    it "derives nothing for an account that already holds a checkpoint" do
      create(:checkpoint, account: account, closed_on: Date.new(2025, 10, 31))

      result = import(csv_content, format: :td_chequing)

      expect(result.derived_checkpoint).to be_nil
      expect(account.checkpoints.count).to eq 1
    end

    it "derives nothing from a format that carries no balance" do
      mastercard = create(:account, name: "Mastercard")
      content = <<~CSV
        "Description","Type","Card Holder Name","Date","Time","Amount"
        "TIM HORTONS #1723","PURCHASE","JOHN DOE","12/11/2025","01:35 AM","-1.92"
      CSV

      result = import(content, format: :mastercard, into: mastercard)

      expect(result.derived_checkpoint).to be_nil
      expect(mastercard.checkpoints).to be_empty
    end
  end

  describe "suggesting the closing checkpoint" do
    let(:csv_content) do
      <<~CSV
        "2025-11-14","ACME Corp  PAY",,"1000.00","1500.00"
        "2025-11-17","UX215 TFR-TO C1234567","800.00",,"700.00"
      CSV
    end

    it "offers the file's last closing balance without recording it" do
      result = import(csv_content, format: :td_chequing)

      expect(result.suggested_checkpoint.closed_on).to eq Date.new(2025, 11, 17)
      expect(result.suggested_checkpoint.balance_cents).to eq 700_00
      expect(account.checkpoints.where(closed_on: Date.new(2025, 11, 17))).to be_empty
    end

    it "offers nothing when the account already asserts that day's close" do
      create(:checkpoint, account: account, closed_on: Date.new(2025, 11, 17), balance_cents: 700_00)

      expect(import(csv_content, format: :td_chequing).suggested_checkpoint).to be_nil
    end

    it "offers nothing from a format that carries no balance" do
      mastercard = create(:account, name: "Mastercard")
      content = <<~CSV
        "Description","Type","Card Holder Name","Date","Time","Amount"
        "TIM HORTONS #1723","PURCHASE","JOHN DOE","12/11/2025","01:35 AM","-1.92"
      CSV

      expect(import(content, format: :mastercard, into: mastercard).suggested_checkpoint).to be_nil
    end
  end

  describe "matching rows by occurrence" do
    it "imports two identical purchases on one day as two" do
      content = <<~CSV
        "2025-11-14","ACME Corp  PAY",,"1000.00","1500.00"
        "2025-11-14","ACME Corp  PAY",,"1000.00","2500.00"
      CSV

      result = import(content, format: :td_chequing)

      expect(result.imported_count).to eq 2
      expect(result.skipped_count).to eq 0
      expect(account.transactions.where(description: "ACME Corp  PAY").count).to eq 2
    end

    it "contributes nothing from a re-imported overlapping period" do
      content = <<~CSV
        "2025-11-14","ACME Corp  PAY",,"1000.00","1500.00"
        "2025-11-17","UX215 TFR-TO C1234567","800.00",,"700.00"
      CSV

      import(content, format: :td_chequing)
      result = import(content, format: :td_chequing)

      expect(result.imported_count).to eq 0
      expect(result.skipped_count).to eq 2
      expect(account.transactions.count).to eq 2
    end

    it "contributes only the occurrences after the ones already held" do
      create(:transaction, account: account, occurred_on: Time.zone.parse("2025-11-14 00:00"),
                           description: "ACME Corp  PAY", amount: 1000.00, entry_type: :income)

      content = <<~CSV
        "2025-11-14","ACME Corp  PAY",,"1000.00","1500.00"
        "2025-11-14","ACME Corp  PAY",,"1000.00","2500.00"
        "2025-11-14","ACME Corp  PAY",,"1000.00","3500.00"
      CSV

      result = import(content, format: :td_chequing)

      expect(result.skipped_count).to eq 1
      expect(result.imported_count).to eq 2
      expect(account.transactions.where(description: "ACME Corp  PAY").count).to eq 3
    end

    it "ignores the balance column, which is not part of a row's identity" do
      # The old rule tiebroke on balance, so a re-import at a different balance
      # duplicated the row. Balance is provenance, not identity.
      import(%("2025-11-14","ACME Corp  PAY",,"1000.00","1500.00"\n), format: :td_chequing)

      result = import(%("2025-11-14","ACME Corp  PAY",,"1000.00","9999.00"\n), format: :td_chequing)

      expect(result.imported_count).to eq 0
      expect(result.skipped_count).to eq 1
    end

    it "reports what it skipped" do
      content = %("2025-11-14","ACME Corp  PAY",,"1000.00","1500.00"\n)
      import(content, format: :td_chequing)

      skipped = import(content, format: :td_chequing).skipped_duplicates

      expect(skipped.size).to eq 1
      expect(skipped.first.description).to eq "ACME Corp  PAY"
      expect(skipped.first.amount_cents).to eq 100_000
      expect(skipped.first.entry_type).to eq :income
    end

    it "lets a Mastercard's genuine repeat charge through" do
      # The parser writes no balance, so the old tiebreak could never engage and
      # every legitimate second purchase of a day was discarded.
      mastercard = create(:account, name: "Mastercard")
      content = <<~CSV
        "Description","Type","Card Holder Name","Date","Time","Amount"
        "TIM HORTONS #1723","PURCHASE","JOHN DOE","12/11/2025","01:35 AM","-1.92"
        "TIM HORTONS #1723","PURCHASE","JOHN DOE","12/11/2025","01:35 AM","-1.92"
      CSV

      result = import(content, format: :mastercard, into: mastercard)

      expect(result.imported_count).to eq 2
      expect(result.skipped_count).to eq 0
      expect(mastercard.transactions.count).to eq 2
    end

    it "still contributes nothing on a Mastercard re-import" do
      mastercard = create(:account, name: "Mastercard")
      content = <<~CSV
        "Description","Type","Card Holder Name","Date","Time","Amount"
        "TIM HORTONS #1723","PURCHASE","JOHN DOE","12/11/2025","01:35 AM","-1.92"
      CSV

      import(content, format: :mastercard, into: mastercard)
      result = import(content, format: :mastercard, into: mastercard)

      expect(result.imported_count).to eq 0
      expect(result.skipped_count).to eq 1
      expect(mastercard.transactions.count).to eq 1
    end
  end

  describe "provenance" do
    it "records the file and the row it came from" do
      csv_import = create(:csv_import, account: account, user: user)
      content = <<~CSV
        "2025-11-14","ACME Corp  PAY",,"1000.00","1500.00"
        "2025-11-17","UX215 TFR-TO C1234567","800.00",,"700.00"
      CSV

      import(content, format: :td_chequing, csv_import: csv_import)

      rows = account.transactions.order(:occurred_on)
      expect(rows.map(&:csv_import_id)).to all(eq(csv_import.id))
      expect(rows.map(&:import_row_number)).to eq([ 1, 2 ])
      expect(rows.first).to be_imported
    end

    it "imports without one when no file is being retained" do
      import(%("2025-11-14","ACME Corp  PAY",,"1000.00","1500.00"\n), format: :td_chequing)

      expect(account.transactions.first.csv_import_id).to be_nil
      expect(account.transactions.first).not_to be_imported
    end
  end

  describe "#import with mastercard format" do
    let(:account) { create(:account, name: "Mastercard") }

    it "imports purchases as expenses" do
      content = <<~CSV
        "Description","Type","Card Holder Name","Date","Time","Amount"
        "TIM HORTONS #1723","PURCHASE","JOHN DOE","12/11/2025","01:35 AM","-1.92"
        "LOBLAWS MAIN ST","PURCHASE","JOHN DOE","12/11/2025","01:25 AM","-79.05"
      CSV

      result = import(content, format: :mastercard)

      expect(result.imported_count).to eq 2
      expect(result.error_count).to eq 0

      transactions = account.transactions.order(:amount_cents)
      expect(transactions.first.entry_type).to eq "expense"
      expect(transactions.first.amount).to eq Money.new(192, :cad)
      expect(transactions.first.description).to eq "TIM HORTONS #1723"
      expect(transactions.second.amount).to eq Money.new(7905, :cad)
    end
  end

  describe "#import with td_visa format" do
    let(:account) { create(:account, name: "TD Visa") }

    it "imports charges as expenses and keeps their printed balances" do
      content = <<~CSV
        11/24/2025,BALANCE PROTECTION INS,20.67,,2109.88
        11/23/2025,TIM HORTONS #0788,3.70,,1924.29
      CSV

      result = import(content, format: :td_visa)

      expect(result.imported_count).to eq 2
      transactions = account.transactions.order(:occurred_on)
      expect(transactions.map(&:entry_type)).to eq %w[expense expense]
      expect(transactions.first.balance_cents).to eq 192_429
      expect(transactions.second.balance_cents).to eq 210_988
    end
  end

  describe "#import with an unknown format" do
    it "raises an error" do
      expect { import("data", format: :unknown) }.to raise_error(ArgumentError, /Unknown import format/)
    end
  end
end
