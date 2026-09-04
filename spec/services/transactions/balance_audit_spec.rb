# frozen_string_literal: true

require "rails_helper"

RSpec.describe Transactions::BalanceAudit do
  let(:account) { create(:account, name: "TD Chequing", import_format: :td_chequing) }

  def row(account:, on:, amount:, type: :expense, balance: nil, number: nil, file: nil)
    create(:transaction,
           account: account,
           occurred_on: on.is_a?(String) ? Time.zone.parse(on) : on,
           amount: amount,
           entry_type: type,
           balance_cents: balance,
           import_row_number: number,
           csv_import: file)
  end

  describe "#supported?" do
    it "is true for a format whose export carries a running balance" do
      expect(described_class.new(account)).to be_supported
      expect(described_class.new(create(:account, import_format: :td_visa))).to be_supported
    end

    it "is false for a format that carries none" do
      mastercard = create(:account, import_format: :mastercard)

      audit = described_class.new(mastercard)

      expect(audit).not_to be_supported
      expect(audit.pairs).to be_empty
    end

    it "audits nothing on an account with no format at all" do
      expect(described_class.new(create(:account))).not_to be_supported
    end
  end

  describe "the chain the bank asserts" do
    it "passes when the printed balance moves by the row's own amount" do
      row(account: account, on: "2025-11-14 00:00", amount: 1000.00, type: :income, balance: 150_000)
      row(account: account, on: "2025-11-17 00:00", amount: 800.00, balance: 70_000)

      audit = described_class.new(account)

      expect(audit.checked_count).to eq 1
      expect(audit).to be_balanced
      expect(audit.violations).to be_empty
    end

    it "reports the pair a violation falls between, not a culprit" do
      earlier = row(account: account, on: "2025-11-14 00:00", amount: 1000.00, type: :income, balance: 150_000)
      later = row(account: account, on: "2025-11-17 00:00", amount: 800.00, balance: 60_000)

      violation = described_class.new(account).violations.sole

      expect(violation.earlier).to eq earlier
      expect(violation.later).to eq later
      # The column fell by 900; the row accounts for 800 of it.
      expect(violation.actual_cents).to eq(-90_000)
      expect(violation.expected_cents).to eq(-80_000)
      expect(violation.residual_cents).to eq(-10_000)
    end

    it "signs the residual by how far the column moved beyond the row" do
      row(account: account, on: "2025-11-14 00:00", amount: 1000.00, type: :income, balance: 150_000)
      row(account: account, on: "2025-11-17 00:00", amount: 800.00, balance: 80_000)

      expect(described_class.new(account).violations.sole.residual_cents).to eq 10_000
    end

    it "reads a credit card's printed debt as a negative balance" do
      visa = create(:account, import_format: :td_visa)
      # The card owed 1000.00, then a 20.67 charge took it to 1020.67.
      row(account: visa, on: "2025-11-23 00:00", amount: 500.00, balance: 100_000)
      row(account: visa, on: "2025-11-24 00:00", amount: 20.67, balance: 102_067)

      audit = described_class.new(visa)

      expect(audit.violations).to be_empty
      expect(audit.pairs.sole.actual_cents).to eq(-2_067)
    end

    it "reads a payment against a card as income raising the balance" do
      visa = create(:account, import_format: :td_visa)
      row(account: visa, on: "2025-11-23 00:00", amount: 500.00, balance: 100_000)
      row(account: visa, on: "2025-11-24 00:00", amount: 300.00, type: :income, balance: 70_000)

      expect(described_class.new(visa).violations).to be_empty
    end
  end

  describe "suspending the chain" do
    it "does not audit across a row carrying no balance" do
      # A hand-entered row moves the account without the bank having recorded
      # it. Auditing across it would report a violation substantiating nothing.
      row(account: account, on: "2025-11-14 00:00", amount: 1000.00, type: :income, balance: 150_000)
      row(account: account, on: "2025-11-15 00:00", amount: 50.00, balance: nil)
      row(account: account, on: "2025-11-17 00:00", amount: 800.00, balance: 70_000)

      audit = described_class.new(account)

      expect(audit.checked_count).to eq 0
      expect(audit).to be_balanced
      expect(audit.suspension_count).to eq 2
    end

    it "does not audit across the join between two files" do
      # Adjacent in the account, never adjacent in any statement.
      march = create(:csv_import, account: account, filename: "march.csv")
      april = create(:csv_import, account: account, filename: "april.csv")
      row(account: account, on: "2025-03-01 00:00", amount: 10.00, balance: 150_000, number: 1, file: march)
      row(account: account, on: "2025-03-02 00:00", amount: 10.00, balance: 149_000, number: 2, file: march)
      row(account: account, on: "2025-04-01 00:00", amount: 10.00, balance: 148_000, number: 1, file: april)
      row(account: account, on: "2025-04-02 00:00", amount: 10.00, balance: 147_000, number: 2, file: april)

      audit = described_class.new(account)

      expect(audit.checked_count).to eq 2
      expect(audit).to be_balanced
      expect(audit.suspension_count).to eq 1
    end

    it "counts no suspension on an account with a single unbroken chain" do
      row(account: account, on: "2025-11-14 00:00", amount: 1000.00, type: :income, balance: 150_000)
      row(account: account, on: "2025-11-17 00:00", amount: 800.00, balance: 70_000)

      expect(described_class.new(account).suspension_count).to eq 0
    end
  end

  describe "the order it walks rows in" do
    it "orders rows sharing a date by their number within the file" do
      file = create(:csv_import, account: account)
      # Inserted out of order: only the row numbers say which came first.
      second = row(account: account, on: "2025-11-14 00:00", amount: 300.00, balance: 120_000, number: 2, file: file)
      first = row(account: account, on: "2025-11-14 00:00", amount: 200.00, balance: 150_000, number: 1, file: file)

      pair = described_class.new(account).pairs.sole

      expect(pair.earlier).to eq first
      expect(pair.later).to eq second
      expect(pair).to be_balanced
    end

    it "walks a newest-first export backwards through its row numbers" do
      visa = create(:account, import_format: :td_visa)
      file = create(:csv_import, account: visa)
      # TD's Visa export lists the most recent row first, so row 1 happened last.
      last = row(account: visa, on: "2025-11-14 00:00", amount: 20.00, balance: 102_000, number: 1, file: file)
      first = row(account: visa, on: "2025-11-14 00:00", amount: 50.00, balance: 100_000, number: 2, file: file)

      pair = described_class.new(visa).pairs.sole

      expect(pair.earlier).to eq first
      expect(pair.later).to eq last
      expect(pair).to be_balanced
    end

    it "falls back to insertion order for rows predating the row number" do
      earlier = row(account: account, on: "2025-11-14 00:00", amount: 200.00, balance: 150_000)
      later = row(account: account, on: "2025-11-14 00:00", amount: 300.00, balance: 147_000)

      pair = described_class.new(account).pairs.sole

      expect([ pair.earlier, pair.later ]).to eq [ earlier, later ]
    end
  end

  describe "how strongly a violation is evidenced" do
    it "marks a same-day pair of unnumbered rows as resting on an assumed order" do
      row(account: account, on: "2025-11-14 00:00", amount: 200.00, balance: 150_000)
      row(account: account, on: "2025-11-14 00:00", amount: 300.00, balance: 140_000)

      expect(described_class.new(account).violations.sole).to be_order_assumed
    end

    it "does not, once the file's own row numbers fix the order" do
      file = create(:csv_import, account: account)
      row(account: account, on: "2025-11-14 00:00", amount: 200.00, balance: 150_000, number: 1, file: file)
      row(account: account, on: "2025-11-14 00:00", amount: 300.00, balance: 140_000, number: 2, file: file)

      expect(described_class.new(account).violations.sole).not_to be_order_assumed
    end

    it "does not for rows dated apart, which cannot be out of order" do
      row(account: account, on: "2025-11-14 00:00", amount: 200.00, balance: 150_000)
      row(account: account, on: "2025-11-21 00:00", amount: 300.00, balance: 140_000)

      violation = described_class.new(account).violations.sole
      expect(violation).not_to be_same_day
      expect(violation).not_to be_order_assumed
    end
  end

  describe "#residual_cents" do
    it "totals what the violations leave unexplained" do
      row(account: account, on: "2025-11-14 00:00", amount: 200.00, balance: 150_000)
      # The column falls 10,000 against a row explaining 30,000, then 15,000
      # against a row explaining 10,000.
      row(account: account, on: "2025-11-15 00:00", amount: 300.00, balance: 140_000)
      row(account: account, on: "2025-11-16 00:00", amount: 100.00, balance: 125_000)

      audit = described_class.new(account)

      expect(audit.violations.size).to eq 2
      expect(audit.residual_cents).to eq(20_000 + -5_000)
    end

    it "is zero on an account whose chain holds throughout" do
      row(account: account, on: "2025-11-14 00:00", amount: 200.00, balance: 150_000)
      row(account: account, on: "2025-11-15 00:00", amount: 300.00, balance: 120_000)

      expect(described_class.new(account).residual_cents).to be_zero
    end
  end

  it "writes nothing" do
    row(account: account, on: "2025-11-14 00:00", amount: 200.00, balance: 150_000)
    row(account: account, on: "2025-11-15 00:00", amount: 300.00, balance: 140_000)

    expect { described_class.new(account).violations }.not_to change { Transaction.count }
    expect(Transaction.pluck(:balance_cents)).to eq [ 150_000, 140_000 ]
  end
end
