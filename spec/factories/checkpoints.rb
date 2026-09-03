FactoryBot.define do
  factory :checkpoint do
    association :account
    closed_on { Date.current }
    balance_cents { 100_00 }
    source { :verified }

    after(:build) do |checkpoint|
      checkpoint.acted_by ||= create(:user)
    end
  end
end
