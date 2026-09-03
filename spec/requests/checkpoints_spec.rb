# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Checkpoints", type: :request do
  let(:user) { create(:user) }
  let(:account) { create(:account, name: "TD joint savings") }

  before { sign_in user, scope: :user }

  describe "GET /accounts/:account_id/checkpoints/new" do
    it "renders the form" do
      get new_account_checkpoint_path(account)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Record checkpoint")
      expect(response.body).to include(account.name)
    end

    it "prefills what an import offered" do
      get new_account_checkpoint_path(account, closed_on: "2025-12-18", balance_cents: 1_537_243)

      expect(response.body).to include(%(value="2025-12-18"))
      expect(response.body).to include(%(value="15372.43"))
    end
  end

  describe "POST /accounts/:account_id/checkpoints" do
    it "records the checkpoint and reports the balance it produces" do
      create(:transaction, account: account, entry_type: :income, amount: 2.50,
                           occurred_on: Time.zone.parse("2025-12-19 12:00"))

      expect {
        post account_checkpoints_path(account),
             params: { checkpoint: { closed_on: "2025-12-18", balance: "15372.43" } }
      }.to change(account.checkpoints, :count).by(1)

      expect(response).to redirect_to(account_path(account))
      follow_redirect!
      expect(response.body).to include("$15,374.93")
    end

    it "marks a checkpoint a person entered as verified" do
      post account_checkpoints_path(account),
           params: { checkpoint: { closed_on: "2025-12-18", balance: "15372.43" } }

      expect(account.checkpoints.last).to be_verified
    end

    it "records the creation against the acting user" do
      post account_checkpoints_path(account),
           params: { checkpoint: { closed_on: "2025-12-18", balance: "15372.43" } }

      revision = account.checkpoints.last.revisions.sole
      expect(revision.action).to eq("create")
      expect(revision.user).to eq(user)
    end

    it "refuses a second assertion about the same day" do
      create(:checkpoint, account: account, closed_on: Date.new(2025, 12, 18))

      post account_checkpoints_path(account),
           params: { checkpoint: { closed_on: "2025-12-18", balance: "1.00" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(account.checkpoints.count).to eq 1
    end
  end

  describe "PATCH /checkpoints/:id" do
    it "records the edit and promotes a derived checkpoint to verified" do
      checkpoint = create(:checkpoint, account: account, source: :derived, balance_cents: 100_00)

      patch checkpoint_path(checkpoint), params: { checkpoint: { balance: "105.00" } }

      expect(response).to redirect_to(account_path(account))
      expect(checkpoint.reload.balance_cents).to eq 105_00
      expect(checkpoint).to be_verified
      expect(checkpoint.revisions.newest_first.first.action).to eq("update")
      expect(checkpoint.revisions.newest_first.first.user).to eq(user)
    end

    it "flags an adjustment the edit left stale rather than removing it" do
      create(:checkpoint, account: account, closed_on: Date.new(2025, 1, 31), balance_cents: 100_00)
      closing = create(:checkpoint, account: account, closed_on: Date.new(2025, 2, 28), balance_cents: 110_00)
      adjustment = create(:transaction, account: account, entry_type: :income, amount: 10,
                                        occurred_on: Time.zone.parse("2025-02-15 12:00"),
                                        adjusted_checkpoint: closing)

      patch checkpoint_path(closing), params: { checkpoint: { balance: "115.00" } }

      follow_redirect!
      expect(response.body).to include("no longer close the gap")
      expect(Transaction.exists?(adjustment.id)).to be(true)
    end
  end

  describe "DELETE /checkpoints/:id" do
    it "deletes the checkpoint" do
      create(:checkpoint, account: account, closed_on: Date.new(2025, 1, 31))
      checkpoint = create(:checkpoint, account: account, closed_on: Date.new(2025, 2, 28))

      delete checkpoint_path(checkpoint)

      follow_redirect!
      expect(response.body).to include("Checkpoint deleted")
      expect(account.checkpoints.count).to eq 1
    end

    it "warns when it removed the account's last anchor" do
      checkpoint = create(:checkpoint, account: account)

      delete checkpoint_path(checkpoint)

      follow_redirect!
      expect(response.body).to include("sum of every transaction")
      expect(account.reload).not_to be_anchored
    end
  end
end
