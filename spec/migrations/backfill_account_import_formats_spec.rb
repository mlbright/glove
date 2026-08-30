# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260830120001_backfill_account_import_formats")

# The backfill runs once against production, so its name matching gets one
# chance to be right. These are the real account names as they stand today.
RSpec.describe BackfillAccountImportFormats do
  def run_backfill
    ActiveRecord::Migration.suppress_messages { described_class.new.up }
  end

  it "gives each existing account the format its bank exports" do
    mastercard = create(:account, name: "PC Financial Mastercard", import_format: nil)
    visa = create(:account, name: "TD personal VISA", import_format: nil)
    joint_chequing = create(:account, name: "TD joint chequing", import_format: nil)
    personal_chequing = create(:account, name: "TD personal chequing", import_format: nil)
    savings = create(:account, name: "TD joint savings", import_format: nil)

    run_backfill

    expect(mastercard.reload.import_format).to eq("mastercard")
    expect(visa.reload.import_format).to eq("td_visa")
    expect(joint_chequing.reload.import_format).to eq("td_chequing")
    expect(personal_chequing.reload.import_format).to eq("td_chequing")
    expect(savings.reload.import_format).to eq("td_chequing")
  end

  it "leaves unrecognised accounts without a format rather than guessing" do
    test_account = create(:account, name: "Test Mastercard", import_format: nil)

    run_backfill

    expect(test_account.reload.import_format).to be_nil
    expect(test_account).not_to be_importable
  end

  it "does not overwrite a format someone already set" do
    account = create(:account, name: "TD joint savings", import_format: "td_visa")

    run_backfill

    expect(account.reload.import_format).to eq("td_visa")
  end

  it "can run twice" do
    account = create(:account, name: "TD personal VISA", import_format: nil)

    run_backfill
    run_backfill

    expect(account.reload.import_format).to eq("td_visa")
  end

  it "maps every name it knows to a format the registry recognises" do
    expect(described_class::FORMATS_BY_NAME.values.uniq)
      .to all(be_in(CsvImports::Format.keys))
  end
end
