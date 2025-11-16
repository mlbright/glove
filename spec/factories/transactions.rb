FactoryBot.define do
  factory :transaction do
    association :user
    association :account
    amount { 25.0 }
    entry_type { :expense }
    occurred_on { Date.current }
    memo { "Coffee" }
    status { :cleared }
  end
end
