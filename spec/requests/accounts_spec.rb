# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Accounts", type: :request do
  let(:user) { create(:user) }
  let(:account) { create(:account, name: "TD joint savings", import_format: "td_chequing") }

  before { sign_in user, scope: :user }

  describe "GET /accounts/:id" do
    it "reports the balance and the checkpoint it hangs off" do
      create(:checkpoint, account: account, closed_on: Date.new(2025, 12, 18), balance_cents: 1_537_243)
      create(:transaction, account: account, entry_type: :income, amount: 2.50,
                           occurred_on: Time.zone.parse("2025-12-19 12:00"))

      get account_path(account)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("$15,374.93")
      expect(response.body).to include("December 18, 2025")
      expect(response.body).to include("Verified")
    end

    it "warns when the account has no checkpoint to anchor to" do
      create(:transaction, account: account)

      get account_path(account)

      expect(response.body).to include("No checkpoint")
      expect(response.body).to include("sum of every transaction")
    end

    it "marks a transaction that sits behind the checkpoint" do
      create(:checkpoint, account: account, closed_on: Date.new(2025, 12, 18), balance_cents: 100_00)
      create(:transaction, account: account, description: "Older row",
                           occurred_on: Time.zone.parse("2025-06-01 12:00"))

      get account_path(account)

      expect(response.body).to include("Before checkpoint")
    end

    it "localises a discrepancy to the interval that contains it and offers to close it" do
      create(:checkpoint, account: account, closed_on: Date.new(2025, 1, 31), balance_cents: 100_00)
      create(:transaction, account: account, entry_type: :income, amount: 30,
                           occurred_on: Time.zone.parse("2025-02-10 12:00"))
      closing = create(:checkpoint, account: account, closed_on: Date.new(2025, 2, 28), balance_cents: 140_00)

      get account_path(account)

      expect(response.body.gsub(/\s+/, " ")).to include("Off by $10")
      expect(response.body.gsub(/\s+/, " ")).to include("1 transaction since January 31, 2025 reach $130")
      expect(response.body).to include(checkpoint_adjustment_path(closing))
    end

    it "shows an interval that balances as balancing" do
      create(:checkpoint, account: account, closed_on: Date.new(2025, 1, 31), balance_cents: 100_00)
      create(:transaction, account: account, entry_type: :income, amount: 30,
                           occurred_on: Time.zone.parse("2025-02-10 12:00"))
      create(:checkpoint, account: account, closed_on: Date.new(2025, 2, 28), balance_cents: 130_00)

      get account_path(account)

      expect(response.body).to include("Balances")
      expect(response.body).not_to include("Off by")
    end

    it "flags a stale adjustment rather than offering to close the gap again" do
      create(:checkpoint, account: account, closed_on: Date.new(2025, 1, 31), balance_cents: 100_00)
      closing = create(:checkpoint, account: account, closed_on: Date.new(2025, 2, 28), balance_cents: 110_00)
      create(:transaction, account: account, entry_type: :income, amount: 10,
                           occurred_on: Time.zone.parse("2025-02-15 12:00"), adjusted_checkpoint: closing)
      closing.update!(balance_cents: 115_00)

      get account_path(account)

      expect(response.body).to include("no longer closes the gap")
      expect(response.body).not_to include(checkpoint_adjustment_path(closing))
    end

    it "lists the files imported into the account" do
      create(:csv_import, account: account, user: user, filename: "december.csv")

      get account_path(account)

      expect(response.body).to include("december.csv")
      expect(response.body).to include("Imported files")
    end
  end
end
