# frozen_string_literal: true

require "rails_helper"

RSpec.describe CsvImports::MastercardParser do
  describe "#parse" do
    it "parses a valid CSV with purchases (expense)" do
      csv_content = <<~CSV
        "Description","Type","Card Holder Name","Date","Time","Amount"
        "TIM HORTONS #1723","PURCHASE","JOHN DOE","12/11/2025","01:35 AM","-1.92"
      CSV

      result = described_class.new(csv_content).parse

      expect(result.success?).to be true
      expect(result.rows.count).to eq 1

      row = result.rows.first
      expect(row.occurred_at).to eq Time.new(2025, 12, 11, 1, 35)
      expect(row.description).to eq "TIM HORTONS #1723"
      expect(row.amount_cents).to eq 192
      expect(row.entry_type).to eq :expense
    end

    it "parses a valid CSV with payments (income)" do
      csv_content = <<~CSV
        "Description","Type","Card Holder Name","Date","Time","Amount"
        "PAYMENT THANK YOU","PAYMENT","JOHN DOE","12/11/2025","01:35 AM","500.00"
      CSV

      result = described_class.new(csv_content).parse

      expect(result.success?).to be true
      expect(result.rows.count).to eq 1

      row = result.rows.first
      expect(row.entry_type).to eq :income
      expect(row.amount_cents).to eq 50_000
      expect(row.description).to eq "PAYMENT THANK YOU (PAYMENT)"
    end

    it "parses multiple rows" do
      csv_content = <<~CSV
        "Description","Type","Card Holder Name","Date","Time","Amount"
        "TIM HORTONS #1723","PURCHASE","JOHN DOE","12/11/2025","01:35 AM","-1.92"
        "LOBLAWS MAIN ST","PURCHASE","JOHN DOE","12/11/2025","01:25 AM","-79.05"
        "CANADIAN TIRE #654","PURCHASE","JOHN DOE","12/11/2025","01:01 AM","-50.83"
        "ESSO CIRCLE K","PURCHASE","JOHN DOE","12/09/2025","05:00 AM","-24.27"
      CSV

      result = described_class.new(csv_content).parse

      expect(result.success?).to be true
      expect(result.rows.count).to eq 4
    end

    it "skips blank lines" do
      csv_content = <<~CSV
        "Description","Type","Card Holder Name","Date","Time","Amount"
        "TIM HORTONS #1723","PURCHASE","JOHN DOE","12/11/2025","01:35 AM","-1.92"

        "LOBLAWS MAIN ST","PURCHASE","JOHN DOE","12/11/2025","01:25 AM","-79.05"
      CSV

      result = described_class.new(csv_content).parse

      expect(result.rows.count).to eq 2
    end

    it "records errors for invalid rows" do
      csv_content = <<~CSV
        "Description","Type","Card Holder Name","Date","Time","Amount"
        "TIM HORTONS #1723","PURCHASE","JOHN DOE","invalid-date","01:35 AM","-1.92"
      CSV

      result = described_class.new(csv_content).parse

      expect(result.failure?).to be true
      expect(result.errors.count).to eq 1
      expect(result.errors.first[:error]).to include("Invalid date/time format")
    end

    it "includes non-PURCHASE transaction types in description" do
      csv_content = <<~CSV
        "Description","Type","Card Holder Name","Date","Time","Amount"
        "REFUND FROM STORE","REFUND","JOHN DOE","12/11/2025","01:35 AM","25.00"
      CSV

      result = described_class.new(csv_content).parse

      expect(result.rows.first.description).to eq "REFUND FROM STORE (REFUND)"
    end

    it "handles amounts with large values" do
      csv_content = <<~CSV
        "Description","Type","Card Holder Name","Date","Time","Amount"
        "J DOE NF SPRINGFIELD BR","PURCHASE","JOHN DOE","12/07/2025","10:43 PM","-226.41"
      CSV

      result = described_class.new(csv_content).parse

      expect(result.rows.first.amount_cents).to eq 22_641
    end
  end
end
