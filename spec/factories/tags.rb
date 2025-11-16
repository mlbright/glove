FactoryBot.define do
  factory :tag do
    association :user
    sequence(:name) { |n| "Tag #{n}" }
    color { "#FF0000" }
    slug { name.parameterize }
  end
end
