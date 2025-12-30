# frozen_string_literal: true

require "rails_helper"

RSpec.describe CsvImports::TdVisaParser do
  describe "#parse" do
    it "parses a valid CSV with debits (expense)" do
      csv_content = "11/24/2025,BALANCE PROTECTION INS,20.67,,2109.88\n"

      result = described_class.new(csv_content).parse

      expect(result.success?).to be true
      expect(result.rows.count).to eq 1

      row = result.rows.first
      expect(row.occurred_at.to_date).to eq Date.new(2025, 11, 24)
      expect(row.description).to eq "BALANCE PROTECTION INS"
      expect(row.amount_cents).to eq 2_067
      expect(row.entry_type).to eq :expense
      expect(row.balance_cents).to eq 210_988
    end

    it "parses a valid CSV with credits (income/payment)" do
      csv_content = "11/24/2025,PAYMENT THANK YOU,,500.00,1609.88\n"

      result = described_class.new(csv_content).parse

      expect(result.success?).to be true
      expect(result.rows.count).to eq 1

      row = result.rows.first
      expect(row.entry_type).to eq :income
      expect(row.amount_cents).to eq 50_000
    end

    it "parses multiple rows" do
      csv_content = <<~CSV
        11/24/2025,BALANCE PROTECTION INS,20.67,,2109.88
        11/24/2025,BALANCE PROTECTION TAX,1.65,,2089.21
        11/23/2025,AMZN Mktp CA*B089V8YG0,163.27,,2087.56
        11/23/2025,TIM HORTONS #0788,3.70,,1924.29
      CSV

      result = described_class.new(csv_content).parse

      expect(result.success?).to be true
      expect(result.rows.count).to eq 4
    end

    it "skips blank lines" do
      csv_content = <<~CSV
        11/24/2025,BALANCE PROTECTION INS,20.67,,2109.88

        11/23/2025,TIM HORTONS #0788,3.70,,1924.29
      CSV

      result = described_class.new(csv_content).parse

      expect(result.rows.count).to eq 2
    end

    it "records errors for invalid rows" do
      csv_content = "invalid-date,Test,100.00,,1000.00\n"

      result = described_class.new(csv_content).parse

      expect(result.failure?).to be true
      expect(result.errors.count).to eq 1
      expect(result.errors.first[:error]).to include("Invalid date format")
    end
  end
end
