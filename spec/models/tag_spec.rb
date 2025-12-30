require "rails_helper"

RSpec.describe Tag, type: :model do
  it "assigns slug automatically" do
    tag = create(:tag, name: "Food Budget", slug: nil)
    expect(tag.slug).to eq("food-budget")
  end
end
