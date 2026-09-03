require "rails_helper"

RSpec.describe Checkpoint, type: :model do
  it "requires a closing date" do
    expect(build(:checkpoint, closed_on: nil)).not_to be_valid
  end

  it "refuses two assertions about the same day's closing balance" do
    account = create(:account)
    create(:checkpoint, account: account, closed_on: Date.new(2025, 6, 30))

    expect(build(:checkpoint, account: account, closed_on: Date.new(2025, 6, 30))).not_to be_valid
  end

  it "allows the same date on a different account" do
    create(:checkpoint, closed_on: Date.new(2025, 6, 30))

    expect(build(:checkpoint, closed_on: Date.new(2025, 6, 30))).to be_valid
  end

  it "accepts a negative closing balance, which is what a credit card has" do
    checkpoint = build(:checkpoint, balance_cents: -140_112)

    expect(checkpoint).to be_valid
    expect(checkpoint.balance).to eq(Money.new(-140_112, :cad))
  end

  describe "#closes_before" do
    it "is the start of the following day, so the closing day itself is inside the checkpoint" do
      checkpoint = build(:checkpoint, closed_on: Date.new(2025, 6, 30))

      expect(checkpoint.closes_before).to eq(Time.zone.parse("2025-07-01 00:00:00"))
    end
  end

  describe "#previous" do
    it "is the checkpoint immediately before it in time" do
      account = create(:account)
      first = create(:checkpoint, account: account, closed_on: Date.new(2025, 1, 31))
      create(:checkpoint, account: account, closed_on: Date.new(2025, 2, 28))
      third = create(:checkpoint, account: account, closed_on: Date.new(2025, 3, 31))

      expect(third.previous.closed_on).to eq(Date.new(2025, 2, 28))
      expect(first.previous).to be_nil
    end
  end

  describe "source" do
    it "promotes a derived checkpoint to verified when a person corrects it" do
      checkpoint = create(:checkpoint, source: :derived, balance_cents: 100_00)

      checkpoint.update!(balance_cents: 105_00)

      expect(checkpoint.reload).to be_verified
    end

    it "promotes on a date correction too" do
      checkpoint = create(:checkpoint, source: :derived, closed_on: Date.new(2025, 6, 30))

      checkpoint.update!(closed_on: Date.new(2025, 6, 29))

      expect(checkpoint.reload).to be_verified
    end

    it "leaves a derived checkpoint derived when nothing about the assertion changes" do
      checkpoint = create(:checkpoint, source: :derived)

      checkpoint.touch

      expect(checkpoint.reload).to be_derived
    end

    it "does not promote over an explicit source the caller set in the same edit" do
      checkpoint = create(:checkpoint, source: :verified, balance_cents: 100_00)

      checkpoint.update!(source: :derived, balance_cents: 105_00)

      expect(checkpoint.reload).to be_derived
    end
  end

  describe "revisions" do
    it "records every edit through the shared revision mechanism" do
      user = create(:user)
      checkpoint = create(:checkpoint, acted_by: user, balance_cents: 100_00)

      checkpoint.acted_by = user
      checkpoint.update!(balance_cents: 105_00)

      expect(checkpoint.revisions.newest_first.map(&:action)).to eq(%w[update create])
      expect(checkpoint.revisions.newest_first.first.change_log).to include("balance_cents")
    end
  end

  it "leaves its adjustments in place when it is deleted, holding them visible" do
    account = create(:account)
    checkpoint = create(:checkpoint, account: account)
    adjustment = create(:transaction, account: account, adjusted_checkpoint: checkpoint)

    checkpoint.destroy

    expect(adjustment.reload.adjusts_checkpoint_id).to be_nil
    expect(Transaction.exists?(adjustment.id)).to be(true)
  end
end
