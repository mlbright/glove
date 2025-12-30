FactoryBot.define do
  factory :transaction do
    association :account
    amount { 25.0 }
    entry_type { :expense }
    occurred_on { Time.current }
    description { "Coffee" }
    status { :cleared }

    after(:build) do |transaction|
      transaction.acted_by ||= create(:user)
    end
  end
end
