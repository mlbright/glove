require "rails_helper"

RSpec.describe Account, type: :model do
  it "calculates balance using income and expenses" do
    account = create(:account)
    create(:transaction, account: account, entry_type: :income, amount: 100)
    create(:transaction, account: account, entry_type: :expense, amount: 40)

    expect(account.balance).to eq(Money.new(6000, :cad))
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
