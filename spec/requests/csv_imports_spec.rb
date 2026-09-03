# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CsvImports", type: :request do
  let(:user) { create(:user) }
  let!(:account) { create(:account, name: "TD Chequing", import_format: "td_chequing") }

  before { sign_in user, scope: :user }

  describe "GET /csv_imports/new" do
    it "renders the form" do
      get new_csv_import_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Import CSV")
      expect(response.body).to include(account.name)
    end

    it "carries each account's import format on its option" do
      visa = create(:account, name: "TD personal VISA", import_format: "td_visa")

      get new_csv_import_path

      expect(response.body).to include(%(data-format="td_chequing"))
      expect(response.body).to include(%(data-format-label="TD Chequing Account"))
      expect(response.body).to include(%(data-format="td_visa"))
      expect(response.body).to include(visa.name)
    end

    it "ships every format's reference block for the client to narrow" do
      get new_csv_import_path

      CsvImports::Format.all.each do |format|
        expect(response.body).to include(%(data-format-key="#{format.key}"))
        expect(response.body).to include(format.label)
      end
    end

    it "disables accounts with no import format and links to their edit page" do
      formatless = create(:account, name: "Cash jar", import_format: nil)

      get new_csv_import_path

      expect(response.body).to include("no import format set")
      expect(response.body).to include(edit_account_path(formatless))
    end

    it "offers no format select of its own" do
      get new_csv_import_path

      expect(response.body).not_to include(%(name="format_type"))
    end
  end

  describe "POST /csv_imports" do
    let(:csv_content) do
      <<~CSV
        "2025-11-14","ACME Corp  PAY",,"1000.00","1500.00"
        "2025-11-17","UX215 TFR-TO C1234567","800.00",,"700.00"
      CSV
    end

    def upload(content = csv_content, filename: "transactions.csv")
      Rack::Test::UploadedFile.new(StringIO.new(content), "text/csv", original_filename: filename)
    end

    it "imports transactions from CSV" do
      # Two rows, two transactions. No synthetic opening balance row: the
      # account's anchor is a checkpoint, not a transaction. See docs/adr/0002.
      expect {
        post csv_imports_path, params: { account_id: account.id, csv_file: upload }
      }.to change(Transaction, :count).by(2)

      expect(response.body).to include("Successfully imported 2 transactions")
    end

    it "derives an opening checkpoint for an account that held nothing" do
      expect {
        post csv_imports_path, params: { account_id: account.id, csv_file: upload }
      }.to change(account.checkpoints, :count).by(1)

      checkpoint = account.checkpoints.chronological.first
      # 1500.00 stands after a 1000.00 deposit on the 14th, so the 13th closed at 500.00.
      expect(checkpoint.closed_on).to eq(Date.new(2025, 11, 13))
      expect(checkpoint.balance_cents).to eq(500_00)
      expect(checkpoint).to be_derived
      expect(account.reload.balance).to eq(Money.new(700_00, :cad))
    end

    it "offers the file's closing balance as a checkpoint rather than recording it" do
      post csv_imports_path, params: { account_id: account.id, csv_file: upload }

      expect(response.body).to include("Closing balance available")
      expect(response.body).to include(CGI.escapeHTML(
        new_account_checkpoint_path(account, closed_on: "2025-11-17", balance_cents: 700_00)
      ))
      expect(account.checkpoints.where(closed_on: Date.new(2025, 11, 17))).to be_empty
    end

    it "retains the uploaded file and records it as the rows' provenance" do
      expect {
        post csv_imports_path, params: { account_id: account.id, csv_file: upload }
      }.to change(CsvImport, :count).by(1)

      csv_import = CsvImport.last
      expect(csv_import.filename).to eq("transactions.csv")
      expect(csv_import.digest).to eq(CsvImport.digest_for(csv_content))
      expect(csv_import.file).to be_attached
      expect(csv_import.file.download).to eq(csv_content)
      expect(csv_import.transactions.pluck(:import_row_number)).to match_array([ 1, 2 ])
    end

    it "contributes nothing on a re-import of the same period" do
      post csv_imports_path, params: { account_id: account.id, csv_file: upload }

      expect {
        post csv_imports_path, params: { account_id: account.id, csv_file: upload }
      }.not_to change(Transaction, :count)

      expect(response.body).to include("Rows Already Held")
    end

    it "requires a CSV file" do
      post csv_imports_path, params: {
        account_id: account.id
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
        csv_file: file
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Please select a valid account")
    end

    it "refuses an account with no import format" do
      formatless = create(:account, name: "Cash jar", import_format: nil)
      file = Rack::Test::UploadedFile.new(
        StringIO.new(csv_content),
        "text/csv",
        original_filename: "transactions.csv"
      )

      expect {
        post csv_imports_path, params: {
          account_id: formatless.id,
          csv_file: file
        }
      }.not_to change(Transaction, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("has no import format set")
    end

    it "ignores a format supplied by the client and uses the account's own" do
      visa_csv = "11/24/2025,BALANCE PROTECTION INS,20.67,,2109.88\n"
      file = Rack::Test::UploadedFile.new(
        StringIO.new(visa_csv),
        "text/csv",
        original_filename: "transactions.csv"
      )

      # The account is td_chequing; a td_visa CSV cannot be read by that parser,
      # so a client-supplied format_type must not talk the server into using it.
      post csv_imports_path, params: {
        account_id: account.id,
        format_type: "td_visa",
        csv_file: file
      }

      expect(Transaction.joins(:account).where(accounts: { id: account.id })
               .where(description: "BALANCE PROTECTION INS")).to be_empty
    end
  end
end
