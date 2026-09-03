require "rails_helper"

RSpec.describe Checkpoints::Audit do
  let(:account) { create(:account) }

  def transaction(on:, amount:, type: :income, **attrs)
    create(:transaction, account: account, entry_type: type, amount: amount,
                         occurred_on: Time.zone.parse("#{on} 12:00"), **attrs)
  end

  it "has no intervals with fewer than two checkpoints" do
    create(:checkpoint, account: account, closed_on: Date.new(2025, 1, 31))

    expect(described_class.new(account).intervals).to be_empty
    expect(described_class.new(account)).to be_balanced
  end

  it "balances when the transactions between two checkpoints reach the second" do
    create(:checkpoint, account: account, closed_on: Date.new(2025, 1, 31), balance_cents: 100_00)
    transaction(on: "2025-02-10", amount: 30)
    transaction(on: "2025-02-20", amount: 5, type: :expense)
    create(:checkpoint, account: account, closed_on: Date.new(2025, 2, 28), balance_cents: 125_00)

    expect(described_class.new(account)).to be_balanced
  end

  it "contains a shortfall inside the interval that holds it" do
    create(:checkpoint, account: account, closed_on: Date.new(2025, 1, 31), balance_cents: 100_00)
    transaction(on: "2025-02-10", amount: 30)
    create(:checkpoint, account: account, closed_on: Date.new(2025, 2, 28), balance_cents: 140_00)
    transaction(on: "2025-03-10", amount: 10)
    create(:checkpoint, account: account, closed_on: Date.new(2025, 3, 31), balance_cents: 150_00)

    audit = described_class.new(account)

    expect(audit.intervals.size).to eq(2)
    expect(audit.discrepancies.map(&:label)).to eq([ "2025-01-31 to 2025-02-28" ])
    expect(audit.discrepancies.first.discrepancy_cents).to eq(10_00)
    expect(audit.discrepancies.first.transaction_count).to eq(1)
  end

  it "puts a transaction dated on a checkpoint's own day inside the interval ending there" do
    create(:checkpoint, account: account, closed_on: Date.new(2025, 1, 31), balance_cents: 100_00)
    transaction(on: "2025-02-28", amount: 25)
    create(:checkpoint, account: account, closed_on: Date.new(2025, 2, 28), balance_cents: 125_00)

    expect(described_class.new(account)).to be_balanced
  end

  it "excludes transactions flagged out of the balance" do
    create(:checkpoint, account: account, closed_on: Date.new(2025, 1, 31), balance_cents: 100_00)
    transaction(on: "2025-02-10", amount: 30, excludes_from_balance: true)
    create(:checkpoint, account: account, closed_on: Date.new(2025, 2, 28), balance_cents: 100_00)

    expect(described_class.new(account)).to be_balanced
  end

  describe "#interval_ending_at" do
    it "is nil for the earliest checkpoint, which has nothing before it" do
      first = create(:checkpoint, account: account, closed_on: Date.new(2025, 1, 31))
      second = create(:checkpoint, account: account, closed_on: Date.new(2025, 2, 28))

      audit = described_class.new(account)

      expect(audit.interval_ending_at(first)).to be_nil
      expect(audit.interval_ending_at(second)).not_to be_nil
    end
  end

  describe "stale adjustments" do
    it "flags an adjustment whose interval stopped balancing after a checkpoint edit" do
      create(:checkpoint, account: account, closed_on: Date.new(2025, 1, 31), balance_cents: 100_00)
      closing = create(:checkpoint, account: account, closed_on: Date.new(2025, 2, 28), balance_cents: 110_00)
      transaction(on: "2025-02-15", amount: 10, adjusted_checkpoint: closing)

      expect(described_class.new(account)).to be_balanced
      expect(described_class.new(account).stale_adjustments).to be_empty

      closing.update!(balance_cents: 115_00)

      audit = described_class.new(account.reload)
      expect(audit.stale_adjustments.map(&:label)).to eq([ "2025-01-31 to 2025-02-28" ])
      expect(audit.stale_adjustments.first.adjustments.size).to eq(1)
    end
  end
end
