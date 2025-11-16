require "rails_helper"

RSpec.describe ImportTemplate, type: :model do
  it "returns mapped attribute for a column" do
    template = build(:import_template, mapping: { "Amount" => "amount" })
    expect(template.attribute_for_column("Amount")).to eq("amount")
  end
end
