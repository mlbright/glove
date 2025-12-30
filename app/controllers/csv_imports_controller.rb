# frozen_string_literal: true

class CsvImportsController < ApplicationController
  SUPPORTED_FORMATS = {
    "td_chequing" => "TD Chequing Account",
    "td_visa" => "TD Visa Credit Card",
    "mastercard" => "PC Financial Mastercard"
  }.freeze

  def new
    @accounts = Account.active.order(:name)
    @formats = SUPPORTED_FORMATS
  end

  def create
    @accounts = Account.active.order(:name)
    @formats = SUPPORTED_FORMATS

    unless params[:csv_file].present?
      flash.now[:alert] = "Please select a CSV file to import."
      return render :new, status: :unprocessable_entity
    end

    account = Account.find_by(id: params[:account_id])
    unless account
      flash.now[:alert] = "Please select a valid account."
      return render :new, status: :unprocessable_entity
    end

    format = params[:format_type]
    unless SUPPORTED_FORMATS.key?(format)
      flash.now[:alert] = "Please select a valid import format."
      return render :new, status: :unprocessable_entity
    end

    file_content = params[:csv_file].read
    importer = CsvImports::Importer.new(user: current_user, account: account, format: format)
    @result = importer.import(file_content)
    @account = account

    if @result.error_count.zero? && @result.skipped_duplicates.empty?
      flash[:notice] = "Successfully imported #{@result.imported_count} transactions."
      redirect_to transactions_path
    elsif @result.error_count.zero?
      flash.now[:notice] = "Successfully imported #{@result.imported_count} transactions. #{@result.skipped_count} duplicates skipped."
      render :result
    else
      flash.now[:alert] = "Import completed with errors."
      render :result, status: :unprocessable_entity
    end
  rescue StandardError => e
    flash.now[:alert] = "Import failed: #{e.message}"
    render :new, status: :unprocessable_entity
  end
end
