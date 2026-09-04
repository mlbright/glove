# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Accounts", type: :request do
  let(:user) { create(:user) }
  let(:account) { create(:account, name: "TD joint savings", import_format: "td_chequing") }

  before { sign_in user, scope: :user }

  describe "GET /accounts/:id row audit" do
    def imported(attrs)
      create(:transaction, { account: account, entry_type: :expense, status: :cleared }.merge(attrs))
    end

    it "reports a chain that holds on every pair" do
      imported(occurred_on: Time.zone.parse("2025-11-14 00:00"), amount: 200.00, balance_cents: 150_000)
      imported(occurred_on: Time.zone.parse("2025-11-15 00:00"), amount: 300.00, balance_cents: 120_000)

      get account_path(account)

      expect(response.body).to include("Row audit")
      expect(response.body).to include("1 pair checked, none in violation")
    end

    it "names the pair a violation falls between and what it leaves unexplained" do
      imported(occurred_on: Time.zone.parse("2025-11-14 00:00"), description: "Rent", amount: 200.00,
               balance_cents: 150_000)
      imported(occurred_on: Time.zone.parse("2025-11-20 00:00"), description: "Groceries", amount: 300.00,
               balance_cents: 130_050)

      get account_path(account)

      expect(response.body).to include("1 violation")
      expect(response.body).to include("Groceries")
      expect(response.body).to include("Rent")
      expect(response.body).to include("$100.50 unexplained")
    end

    it "flags a violation resting on an assumed same-day order as weaker evidence" do
      imported(occurred_on: Time.zone.parse("2025-11-14 00:00"), amount: 200.00, balance_cents: 150_000)
      imported(occurred_on: Time.zone.parse("2025-11-14 00:00"), amount: 300.00, balance_cents: 130_000)

      get account_path(account)

      expect(response.body).to include("Same day, order assumed")
    end

    it "says plainly that an account without a balance column cannot be audited this way" do
      mastercard = create(:account, name: "PC Financial Mastercard", import_format: "mastercard")
      create(:transaction, account: mastercard)

      get account_path(mastercard)

      expect(response.body).to include("Not available on this account")
      expect(response.body).to include("carry no balance column")
      expect(response.body).to include("not a clean bill of health here")
    end

    it "says the same of an account with no import format at all" do
      handwritten = create(:account, name: "Cash", import_format: nil)
      create(:transaction, account: handwritten)

      get account_path(handwritten)

      expect(response.body).to include("Not available on this account")
      expect(response.body).to include("This account has no import format")
    end
  end

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
