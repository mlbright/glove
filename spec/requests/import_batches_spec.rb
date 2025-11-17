require "rails_helper"

RSpec.describe "ImportBatches", type: :request do
  let(:user) { create(:user) }
  let(:template) do
    create(:import_template, user: user, mapping: {
      "Account" => "account_name",
      "Amount" => "amount",
      "Type" => "entry_type",
      "Date" => "occurred_on",
      "Tags" => "tag_list"
    })
  end

  before do
    sign_in user, scope: :user
  end

  it "uploads a CSV and processes it into transactions" do
    file = fixture_file_upload("sample_import.csv", "text/csv")

    post import_batches_path, params: {
      import_batch: {
        import_template_id: template.id,
        csv_file: file
      }
    }

    batch = ImportBatch.last
    expect(response).to redirect_to(import_batch_path(batch))
    expect(batch.source_filename).to eq("sample_import.csv")
    expect(batch).to be_pending

    post start_import_batch_path(batch)

    batch.reload
    expect(batch).to be_completed
    expect(batch.processed_count).to eq(1)
    expect(user.transactions.count).to eq(1)
    expect(user.transactions.first.tags.first.name).to eq("Consulting")
  end
end
