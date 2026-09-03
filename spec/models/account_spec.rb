require "rails_helper"

RSpec.describe Account, type: :model do
  describe "#balance" do
    it "sums every transaction when the account holds no checkpoint" do
      account = create(:account)
      create(:transaction, account: account, entry_type: :income, amount: 100)
      create(:transaction, account: account, entry_type: :expense, amount: 40)

      expect(account).not_to be_anchored
      expect(account.balance).to eq(Money.new(6000, :cad))
    end

    it "anchors to the checkpoint and adds only what is dated strictly after it" do
      account = create(:account)
      create(:transaction, account: account, entry_type: :income, amount: 500,
                           occurred_on: Time.zone.parse("2025-06-01 10:00"))
      create(:checkpoint, account: account, closed_on: Date.new(2025, 6, 30), balance_cents: 100_00)
      create(:transaction, account: account, entry_type: :expense, amount: 25,
                           occurred_on: Time.zone.parse("2025-07-02 10:00"))

      expect(account.balance).to eq(Money.new(75_00, :cad))
    end

    it "counts a transaction dated on the checkpoint's own day as already inside it" do
      account = create(:account)
      create(:checkpoint, account: account, closed_on: Date.new(2025, 6, 30), balance_cents: 100_00)
      create(:transaction, account: account, entry_type: :income, amount: 10,
                           occurred_on: Time.zone.parse("2025-06-30 23:00"))

      expect(account.balance).to eq(Money.new(100_00, :cad))
    end

    it "uses the latest checkpoint when several exist" do
      account = create(:account)
      create(:checkpoint, account: account, closed_on: Date.new(2025, 1, 31), balance_cents: 10_00)
      create(:checkpoint, account: account, closed_on: Date.new(2025, 6, 30), balance_cents: 100_00)
      create(:transaction, account: account, entry_type: :income, amount: 5,
                           occurred_on: Time.zone.parse("2025-03-15 10:00"))
      create(:transaction, account: account, entry_type: :income, amount: 7,
                           occurred_on: Time.zone.parse("2025-07-15 10:00"))

      expect(account.balance).to eq(Money.new(107_00, :cad))
    end

    it "ignores transactions flagged out of the balance" do
      account = create(:account)
      create(:checkpoint, account: account, closed_on: Date.new(2025, 6, 30), balance_cents: 100_00)
      create(:transaction, account: account, entry_type: :income, amount: 40,
                           occurred_on: Time.zone.parse("2025-07-02 10:00"), excludes_from_balance: true)

      expect(account.balance).to eq(Money.new(100_00, :cad))
    end

    it "returns to summing everything when the last checkpoint is deleted" do
      account = create(:account)
      checkpoint = create(:checkpoint, account: account, closed_on: Date.new(2025, 6, 30), balance_cents: 100_00)
      create(:transaction, account: account, entry_type: :income, amount: 500,
                           occurred_on: Time.zone.parse("2025-06-01 10:00"))

      expect(account.balance).to eq(Money.new(100_00, :cad))

      checkpoint.destroy
      expect(account.reload.balance).to eq(Money.new(500_00, :cad))
    end
  end

  describe "import format" do
    it "is optional" do
      account = build(:account, import_format: nil)

      expect(account).to be_valid
      expect(account).not_to be_importable
    end

    it "accepts a format from the registry" do
      account = build(:account, import_format: "td_visa")

      expect(account).to be_valid
      expect(account).to be_importable
      expect(account.import_format_label).to eq("TD Visa Credit Card")
    end

    it "rejects a format no parser knows" do
      account = build(:account, import_format: "chequing_but_belgian")

      expect(account).not_to be_valid
      expect(account.errors[:import_format]).to be_present
    end

    it "can change after the account already has transactions" do
      account = create(:account, import_format: "td_chequing")
      create(:transaction, account: account)

      expect(account.update(import_format: "td_visa")).to be(true)
    end
  end
end
