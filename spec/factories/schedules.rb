FactoryBot.define do
  factory :schedule do
    association :user
    association :account
    sequence(:name) { |n| "Schedule #{n}" }
    frequency { :monthly }
    interval_value { 1 }
    next_occurs_on { Date.current }
  end
end
