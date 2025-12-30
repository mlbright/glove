# frozen_string_literal: true

require "rails_helper"

RSpec.describe CsvImports::TdChequingParser do
  describe "#parse" do
    it "parses a valid CSV with credits (income)" do
      csv_content = %("2025-11-14","ACME Corp  PAY",,"1000.00","1500.00"\n)

      result = described_class.new(csv_content).parse

      expect(result.success?).to be true
      expect(result.rows.count).to eq 1

      row = result.rows.first
      expect(row.occurred_at.to_date).to eq Date.new(2025, 11, 14)
      expect(row.description).to eq "ACME Corp  PAY"
      expect(row.amount_cents).to eq 100_000
      expect(row.entry_type).to eq :income
      expect(row.balance_cents).to eq 150_000
    end

    it "parses a valid CSV with debits (expense)" do
      csv_content = %("2025-11-17","UX215 TFR-TO C1234567","800.00",,"700.00"\n)

      result = described_class.new(csv_content).parse

      expect(result.success?).to be true
      expect(result.rows.count).to eq 1

      row = result.rows.first
      expect(row.occurred_at.to_date).to eq Date.new(2025, 11, 17)
      expect(row.description).to eq "UX215 TFR-TO C1234567"
      expect(row.amount_cents).to eq 80_000
      expect(row.entry_type).to eq :expense
      expect(row.balance_cents).to eq 70_000
    end

    it "parses multiple rows" do
      csv_content = <<~CSV
        "2025-11-14","ACME Corp  PAY",,"1000.00","1500.00"
        "2025-11-17","UX215 TFR-TO C1234567","800.00",,"700.00"
        "2025-11-28","ACME Corp  PAY",,"1000.00","1700.00"
        "2025-11-28","O.D.P. FEE","5.00",,"1695.00"
      CSV

      result = described_class.new(csv_content).parse

      expect(result.success?).to be true
      expect(result.rows.count).to eq 4
    end

    it "skips blank lines" do
      csv_content = <<~CSV
        "2025-11-14","ACME Corp  PAY",,"1000.00","1500.00"

        "2025-11-17","UX215 TFR-TO C1234567","800.00",,"700.00"
      CSV

      result = described_class.new(csv_content).parse

      expect(result.rows.count).to eq 2
    end

    it "records errors for invalid rows" do
      csv_content = <<~CSV
        "invalid-date","Test",,"100.00","1000.00"
      CSV

      result = described_class.new(csv_content).parse

      expect(result.failure?).to be true
      expect(result.errors.count).to eq 1
      expect(result.errors.first[:error]).to include("Invalid date format")
    end
  end
end
