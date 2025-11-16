FactoryBot.define do
  factory :account do
    association :user
    sequence(:name) { |n| "Account #{n}" }
    account_type { :checking }
    color { "#000000" }
    description { "Checking account" }
  end
end
