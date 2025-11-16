FactoryBot.define do
  factory :transaction_tag do
    association :transaction_record, factory: :transaction
    association :tag
  end
end
