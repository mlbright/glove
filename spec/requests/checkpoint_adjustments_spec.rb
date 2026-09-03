# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CheckpointAdjustments", type: :request do
  let(:user) { create(:user) }
  let(:account) { create(:account, name: "TD joint chequing") }

  before { sign_in user, scope: :user }

  # 100.00 on Jan 31, one 30.00 deposit in February, and a February close of
  # 140.00: the account is 10.00 short somewhere inside that month.
  def account_short_by_ten
    create(:checkpoint, account: account, closed_on: Date.new(2025, 1, 31), balance_cents: 100_00)
    create(:transaction, account: account, entry_type: :income, amount: 30,
                         occurred_on: Time.zone.parse("2025-02-10 12:00"))
    create(:checkpoint, account: account, closed_on: Date.new(2025, 2, 28), balance_cents: 140_00)
  end

  it "closes the gap with an ordinary visible row on an explicit instruction" do
    closing = account_short_by_ten

    expect {
      post checkpoint_adjustment_path(closing)
    }.to change(Transaction, :count).by(1)

    adjustment = account.transactions.find_by(description: Transaction::ADJUSTMENT_DESCRIPTION)
    expect(adjustment.amount).to eq Money.new(10_00, :cad)
    expect(adjustment.entry_type).to eq "income"
    expect(adjustment.occurred_on.to_date).to eq Date.new(2025, 2, 28)
    expect(adjustment.adjusted_checkpoint).to eq closing
    expect(adjustment).to be_adjustment
    expect(Checkpoints::Audit.new(account.reload)).to be_balanced
  end

  it "records who asked for it" do
    closing = account_short_by_ten

    post checkpoint_adjustment_path(closing)

    adjustment = account.transactions.find_by(description: Transaction::ADJUSTMENT_DESCRIPTION)
    expect(adjustment.revisions.sole.user).to eq(user)
  end

  it "writes an expense when the account closed lower than its transactions explain" do
    create(:checkpoint, account: account, closed_on: Date.new(2025, 1, 31), balance_cents: 100_00)
    create(:transaction, account: account, entry_type: :income, amount: 30,
                         occurred_on: Time.zone.parse("2025-02-10 12:00"))
    closing = create(:checkpoint, account: account, closed_on: Date.new(2025, 2, 28), balance_cents: 120_00)

    post checkpoint_adjustment_path(closing)

    adjustment = account.transactions.find_by(description: Transaction::ADJUSTMENT_DESCRIPTION)
    expect(adjustment.entry_type).to eq "expense"
    expect(adjustment.amount).to eq Money.new(10_00, :cad)
  end

  it "refuses on the earliest checkpoint, which has no interval behind it" do
    earliest = create(:checkpoint, account: account, closed_on: Date.new(2025, 1, 31))

    expect { post checkpoint_adjustment_path(earliest) }.not_to change(Transaction, :count)

    follow_redirect!
    expect(response.body).to include("earliest one")
  end

  it "refuses when the interval already balances" do
    create(:checkpoint, account: account, closed_on: Date.new(2025, 1, 31), balance_cents: 100_00)
    closing = create(:checkpoint, account: account, closed_on: Date.new(2025, 2, 28), balance_cents: 100_00)

    expect { post checkpoint_adjustment_path(closing) }.not_to change(Transaction, :count)

    follow_redirect!
    expect(response.body).to include("already balances")
  end

  it "leaves an ordinary row that can simply be deleted" do
    closing = account_short_by_ten
    post checkpoint_adjustment_path(closing)
    adjustment = account.transactions.find_by(description: Transaction::ADJUSTMENT_DESCRIPTION)

    delete transaction_path(adjustment)

    expect(Transaction.exists?(adjustment.id)).to be(false)
    expect(Checkpoints::Audit.new(account.reload)).not_to be_balanced
  end
end
