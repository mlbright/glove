# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CsvImports", type: :request do
  let(:user) { create(:user) }
  let!(:account) { create(:account, name: "TD Chequing") }

  before { sign_in user, scope: :user }

  describe "GET /csv_imports/new" do
    it "renders the form" do
      get new_csv_import_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Import CSV")
      expect(response.body).to include(account.name)
    end
  end

  describe "POST /csv_imports" do
    let(:csv_content) do
      <<~CSV
        "2025-11-14","ACME Corp  PAY",,"1000.00","1500.00"
        "2025-11-17","UX215 TFR-TO C1234567","800.00",,"700.00"
      CSV
    end

    it "imports transactions from CSV" do
      file = Rack::Test::UploadedFile.new(
        StringIO.new(csv_content),
        "text/csv",
        original_filename: "transactions.csv"
      )

      # 3 transactions: opening balance + 2 CSV rows
      expect {
        post csv_imports_path, params: {
          account_id: account.id,
          format_type: "td_chequing",
          csv_file: file
        }
      }.to change(Transaction, :count).by(3)

      expect(response).to redirect_to(transactions_path)
      follow_redirect!
      expect(response.body).to include("Successfully imported 3 transactions")
    end

    it "requires a CSV file" do
      post csv_imports_path, params: {
        account_id: account.id,
        format_type: "td_chequing"
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Please select a CSV file")
    end

    it "requires a valid account" do
      file = Rack::Test::UploadedFile.new(
        StringIO.new(csv_content),
        "text/csv",
        original_filename: "transactions.csv"
      )

      post csv_imports_path, params: {
        account_id: 999999,
        format_type: "td_chequing",
        csv_file: file
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Please select a valid account")
    end

    it "requires a valid format" do
      file = Rack::Test::UploadedFile.new(
        StringIO.new(csv_content),
        "text/csv",
        original_filename: "transactions.csv"
      )

      post csv_imports_path, params: {
        account_id: account.id,
        format_type: "invalid_format",
        csv_file: file
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Please select a valid import format")
    end
  end
end
