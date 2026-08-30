# frozen_string_literal: true

require "rails_helper"

RSpec.describe CsvImports::Format do
  it "names a parser that exists for every format" do
    described_class.all.each do |format|
      expect { described_class.parser_for(format.key) }.not_to raise_error
    end
  end

  # The registry is meant to be the only place the set of formats is written
  # down. If these drift, an account can hold a format nothing can parse -- or
  # a parser exists that no account can be given.
  it "stays in step with the Account enum" do
    expect(Account.import_formats.keys).to match_array(described_class.keys)
  end

  it "refuses an unknown key" do
    expect { described_class.fetch("chequing_but_belgian") }
      .to raise_error(ArgumentError, /Unknown import format/)
  end

  it "treats a blank key as no format rather than an error" do
    expect(described_class.find(nil)).to be_nil
    expect(described_class.find("")).to be_nil
  end

  it "knows which formats carry a balance to reconcile" do
    expect(described_class.fetch("td_chequing")).to be_reconciles_balance
    expect(described_class.fetch("td_visa")).to be_reconciles_balance
    expect(described_class.fetch("mastercard")).not_to be_reconciles_balance
  end
end
