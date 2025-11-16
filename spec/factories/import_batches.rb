require "stringio"

FactoryBot.define do
  factory :import_batch do
    association :user
    association :import_template
    status { :pending }
    processed_count { 0 }
    failed_count { 0 }

    after(:build) do |batch|
      next if batch.csv_file.attached?

      csv_content = "Amount,Type\n10,Income"
      batch.csv_file.attach(io: StringIO.new(csv_content), filename: "sample.csv", content_type: "text/csv")
    end
  end
end
