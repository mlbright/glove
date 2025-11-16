FactoryBot.define do
  factory :import_template do
    association :user
    sequence(:name) { |n| "Template #{n}" }
    delimiter { "," }
    header { true }
    mapping { { "Amount" => "amount", "Type" => "entry_type", "Date" => "occurred_on" } }
    column_examples { ["Amount,Type,Date"] }
  end
end
