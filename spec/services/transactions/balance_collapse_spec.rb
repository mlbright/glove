# frozen_string_literal: true

require "rails_helper"

RSpec.describe Transactions::BalanceCollapse do
  let(:user) { create(:user) }
  let(:account) { create(:account, name: "TD Visa", import_format: :td_visa) }

  def charge(balance_cents:, on: "2026-03-24", description: "TIM HORTONS #1723", amount: 7.54)
    create(:transaction, account: account, occurred_on: Time.zone.parse("#{on} 00:00"),
                         description: description, amount: amount, entry_type: :expense,
                         balance_cents: balance_cents)
  end

  describe "#plan" do
    it "discards the later rows of a group sharing one printed balance" do
      kept = charge(balance_cents: 229_547)
      spurious = charge(balance_cents: 230_301)
      duplicate = charge(balance_cents: 230_301)

      groups = described_class.new(account).plan.groups

      # 229_547 stands alone; the pair at 230_301 cannot both be genuine.
      expect(groups.size).to eq 1
      expect(groups.first.keep_id).to eq spurious.id
      expect(groups.first.discard_ids).to eq [ duplicate.id ]
      expect(account.transactions).to include(kept)
    end

    it "keeps the earliest row of the group" do
      first = charge(balance_cents: 230_301)
      second = charge(balance_cents: 230_301)
      third = charge(balance_cents: 230_301)

      group = described_class.new(account).plan.groups.first

      expect(group.keep_id).to eq first.id
      expect(group.discard_ids).to contain_exactly(second.id, third.id)
    end

    it "leaves rows alone when the bank printed different balances" do
      # The rule may merge rows, never split them. A differing balance is no
      # evidence two rows are distinct — it is what a re-import produces.
      charge(balance_cents: 229_547)
      charge(balance_cents: 230_301)

      expect(described_class.new(account).plan).not_to be_any
    end

    it "leaves a genuine same-day repeat alone" do
      # Two coffees on one day move the balance twice, so the bank prints two
      # balances and the rule has nothing to say about them.
      charge(balance_cents: 230_301)
      charge(balance_cents: 231_055)

      expect(described_class.new(account).plan.removed_count).to eq 0
    end

    it "ignores rows carrying no printed balance" do
      create(:transaction, account: account, description: "Balance adjustment",
                           amount: 10.00, entry_type: :expense, balance_cents: nil)
      create(:transaction, account: account, description: "Balance adjustment",
                           amount: 10.00, entry_type: :expense, balance_cents: nil)

      expect(described_class.new(account).plan).not_to be_any
    end

    it "separates rows that differ in anything but balance" do
      charge(balance_cents: 230_301, description: "TIM HORTONS #1723")
      charge(balance_cents: 230_301, description: "TIM HORTONS #3387")

      expect(described_class.new(account).plan).not_to be_any
    end

    it "reports what removing the rows does to the ledger" do
      charge(balance_cents: 230_301, amount: 7.54)
      charge(balance_cents: 230_301, amount: 7.54)

      # Removing an expense raises the balance by its amount.
      expect(described_class.new(account).plan.ledger_change_cents).to eq 754
    end

    it "lowers the ledger when the discarded row is income" do
      2.times do
        create(:transaction, account: account, occurred_on: Time.zone.parse("2026-03-24 00:00"),
                             description: "PAYMENT - THANK YOU", amount: 100.00,
                             entry_type: :income, balance_cents: 100_000)
      end

      expect(described_class.new(account).plan.ledger_change_cents).to eq(-100_00)
    end

    it "writes nothing" do
      charge(balance_cents: 230_301)
      charge(balance_cents: 230_301)

      expect { described_class.new(account).plan }.not_to change(Transaction, :count)
    end

    it "refuses an account whose format prints no balance" do
      mastercard = create(:account, name: "Mastercard", import_format: :mastercard)

      expect { described_class.new(mastercard).plan }
        .to raise_error(described_class::UnsupportedFormat, /no balance column/)
    end
  end

  describe "#apply!" do
    it "removes the spurious rows and keeps one" do
      charge(balance_cents: 229_547)
      charge(balance_cents: 230_301)
      charge(balance_cents: 230_301)

      expect { described_class.new(account).apply!(acted_by: user) }
        .to change(Transaction, :count).by(-1)
      expect(account.transactions.reload.map(&:balance_cents)).to contain_exactly(229_547, 230_301)
    end

    it "records each removal in the audit trail" do
      charge(balance_cents: 230_301)
      doomed = charge(balance_cents: 230_301)

      described_class.new(account).apply!(acted_by: user)

      revision = Revision.where(record_type: "Transaction", record_id: doomed.id).last
      expect(revision.action).to eq "destroy"
      expect(revision.user).to eq user
      expect(revision.change_log["balance_cents"]).to eq 230_301
    end

    it "returns what it did" do
      charge(balance_cents: 230_301)
      charge(balance_cents: 230_301)

      result = described_class.new(account).apply!(acted_by: user)

      expect(result.removed_count).to eq 1
      expect(result.groups.first.label).to include "TIM HORTONS #1723"
    end

    it "collapses a nine-row group down to the two balances the bank printed" do
      charge(balance_cents: 251_623)
      8.times { charge(balance_cents: 251_729) }

      described_class.new(account).apply!(acted_by: user)

      expect(account.transactions.reload.count).to eq 2
    end
  end
end
