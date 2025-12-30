FactoryBot.define do
  factory :account do
    sequence(:name) { |n| "Account #{n}" }
    color { "#000000" }
    description { "Test account" }
  end
end
