# frozen_string_literal: true

module CsvImports
  # Result object for CSV parsing operations
  Result = Data.define(:rows, :errors) do
    def success?
      errors.empty?
    end

    def partial_success?
      rows.any? && errors.any?
    end

    def failure?
      rows.empty? && errors.any?
    end

    def total_count
      rows.count + errors.count
    end
  end
end
