require "rails_helper"

RSpec.describe CsvImports::RowMatcher do
  # The matcher only reads these four fields off a row, so it does not need a
  # real parser's ParsedRow to be exercised.
  row_struct = Struct.new(:occurred_at, :amount_cents, :description, :entry_type, keyword_init: true)

  let(:account) { create(:account) }

  define_method(:row) do |on: "2025-06-15", cents: 5_00, description: "Coffee", entry_type: :expense|
    row_struct.new(occurred_at: Time.zone.parse("#{on} 09:00"), amount_cents: cents,
                   description: description, entry_type: entry_type)
  end

  def held(on: "2025-06-15", cents: 5_00, description: "Coffee", entry_type: :expense)
    create(:transaction, account: account, occurred_on: Time.zone.parse("#{on} 00:00"),
                         amount_cents: cents, description: description, entry_type: entry_type)
  end

  it "treats every row as new when the account holds nothing" do
    matcher = described_class.new(account)

    expect(matcher.new_occurrence?(row)).to be(true)
    expect(matcher.new_occurrence?(row)).to be(true)
  end

  it "lets a second identical purchase on one day through when the account holds one" do
    held
    matcher = described_class.new(account)

    expect(matcher.new_occurrence?(row)).to be(false)
    expect(matcher.new_occurrence?(row)).to be(true)
  end

  it "contributes nothing from a re-imported overlapping period" do
    3.times { held }
    matcher = described_class.new(account)

    expect(3.times.map { matcher.new_occurrence?(row) }).to all(be(false))
  end

  it "contributes only the occurrences after the Mth" do
    2.times { held }
    matcher = described_class.new(account)

    expect(4.times.map { matcher.new_occurrence?(row) }).to eq([ false, false, true, true ])
  end

  it "separates groups by date, amount, description and entry type" do
    held
    matcher = described_class.new(account)

    expect(matcher.new_occurrence?(row(on: "2025-06-16"))).to be(true)
    expect(matcher.new_occurrence?(row(cents: 6_00))).to be(true)
    expect(matcher.new_occurrence?(row(description: "Tea"))).to be(true)
    expect(matcher.new_occurrence?(row(entry_type: :income))).to be(true)
    expect(matcher.new_occurrence?(row)).to be(false)
  end

  it "matches on the date, not the time of day the parser produced" do
    held(on: "2025-06-15")
    matcher = described_class.new(account)

    expect(matcher.new_occurrence?(row(on: "2025-06-15"))).to be(false)
  end

  it "ignores what a row's balance column says, which is not part of identity" do
    held
    matcher = described_class.new(account)

    expect(matcher.new_occurrence?(row)).to be(false)
  end

  it "counts only the account's own transactions" do
    create(:transaction, account: create(:account), occurred_on: Time.zone.parse("2025-06-15 00:00"),
                         amount_cents: 5_00, description: "Coffee", entry_type: :expense)
    matcher = described_class.new(account)

    expect(matcher.new_occurrence?(row)).to be(true)
  end
end
