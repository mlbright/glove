# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260903120004_migrate_opening_balances_to_checkpoints")

# This runs once against production, so it gets one chance to be right. The
# figures below are the real ones the four TD accounts carry today.
RSpec.describe MigrateOpeningBalancesToCheckpoints do
  def run_migration
    ActiveRecord::Migration.suppress_messages { described_class.new.up }
  end

  def opening_balance(account, on:, amount:, entry_type: :income)
    create(:transaction, account: account, description: "Opening Balance",
                         occurred_on: Time.zone.parse("#{on} 00:00"),
                         amount: amount, entry_type: entry_type)
  end

  it "turns the synthetic row into a checkpoint closing the day before it" do
    account = create(:account, name: "TD joint savings")
    opening_balance(account, on: "2025-12-19", amount: 15_372.43)

    run_migration

    checkpoint = account.checkpoints.sole
    expect(checkpoint.closed_on).to eq Date.new(2025, 12, 18)
    expect(checkpoint.balance_cents).to eq 1_537_243
    expect(checkpoint).to be_derived
  end

  it "removes the row it replaced, so the anchor is not counted twice" do
    account = create(:account)
    opening_balance(account, on: "2025-12-19", amount: 15_372.43)

    run_migration

    expect(account.transactions.where(description: "Opening Balance")).to be_empty
  end

  it "signs an opening balance recorded as an expense as debt" do
    account = create(:account, name: "TD personal VISA")
    opening_balance(account, on: "2025-06-23", amount: 500.00, entry_type: :expense)

    run_migration

    expect(account.checkpoints.sole.balance_cents).to eq(-50_000)
  end

  it "leaves the transactions that predate the anchor visible but not counted" do
    account = create(:account)
    older = create(:transaction, account: account, entry_type: :income, amount: 900,
                                 occurred_on: Time.zone.parse("2025-06-01 12:00"))
    opening_balance(account, on: "2025-12-19", amount: 15_372.43)
    create(:transaction, account: account, entry_type: :income, amount: 2.50,
                         occurred_on: Time.zone.parse("2025-12-19 12:00"))

    run_migration

    expect(Transaction.exists?(older.id)).to be(true)
    # The 2.50 is dated after the checkpoint's own day, so it counts; the 900
    # sits behind the anchor and does not.
    expect(account.reload.balance).to eq Money.new(1_537_493, :cad)
  end

  it "touches no other account" do
    untouched = create(:account, name: "PC Financial Mastercard")
    create(:transaction, account: untouched, description: "TIM HORTONS #1723")
    opening_balance(create(:account), on: "2025-12-19", amount: 100)

    run_migration

    expect(untouched.checkpoints).to be_empty
    expect(untouched.transactions.count).to eq 1
  end

  it "can run twice" do
    account = create(:account)
    opening_balance(account, on: "2025-12-19", amount: 15_372.43)

    run_migration
    run_migration

    expect(account.checkpoints.count).to eq 1
  end

  it "does not overwrite a checkpoint someone already entered for that day" do
    account = create(:account)
    create(:checkpoint, account: account, closed_on: Date.new(2025, 12, 18),
                        balance_cents: 1_500_000, source: :verified)
    opening_balance(account, on: "2025-12-19", amount: 15_372.43)

    run_migration

    checkpoint = account.checkpoints.sole
    expect(checkpoint.balance_cents).to eq 1_500_000
    expect(checkpoint).to be_verified
    expect(account.transactions.where(description: "Opening Balance")).to be_empty
  end

  it "leaves the deleted row's revisions behind, since history outlives the row" do
    account = create(:account)
    row = opening_balance(account, on: "2025-12-19", amount: 15_372.43)
    revision_ids = row.revisions.ids

    expect(revision_ids).not_to be_empty

    run_migration

    expect(Revision.where(id: revision_ids).count).to eq revision_ids.count
  end
end
