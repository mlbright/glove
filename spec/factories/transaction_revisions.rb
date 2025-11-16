FactoryBot.define do
  factory :transaction_revision do
    association :transaction_record, factory: :transaction
    association :user
    action { "create" }
    change_log { { amount: [0, 10] } }
    recorded_at { Time.current }
  end
end
