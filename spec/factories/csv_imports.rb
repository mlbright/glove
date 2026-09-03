FactoryBot.define do
  factory :csv_import do
    association :account
    association :user
    filename { "statement.csv" }
    digest { CsvImport.digest_for(SecureRandom.hex) }
  end
end
