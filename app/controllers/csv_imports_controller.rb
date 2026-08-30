# frozen_string_literal: true

class CsvImportsController < ApplicationController
  def new
    @accounts = Account.active.order(:name)
  end

  def create
    @accounts = Account.active.order(:name)

    unless params[:csv_file].present?
      flash.now[:alert] = "Please select a CSV file to import."
      return render :new, status: :unprocessable_entity
    end

    account = Account.find_by(id: params[:account_id])
    unless account
      flash.now[:alert] = "Please select a valid account."
      return render :new, status: :unprocessable_entity
    end

    # The account decides the format, so an account without one cannot be
    # imported into. The request never carries a format of its own.
    unless account.importable?
      flash.now[:alert] = "#{account.name} has no import format set. Set one on the account before importing."
      return render :new, status: :unprocessable_entity
    end

    file_content = params[:csv_file].read
    importer = CsvImports::Importer.new(
      user: current_user,
      account: account,
      import_format: account.import_format
    )
    @result = importer.import(file_content)
    @account = account

    if @result.error_count.zero? && @result.skipped_duplicates.empty? && @result.warnings.empty?
      flash[:notice] = "Successfully imported #{@result.imported_count} transactions."
      redirect_to transactions_path
    elsif @result.error_count.zero?
      notice_parts = [ "Successfully imported #{@result.imported_count} transactions." ]
      notice_parts << "#{@result.skipped_count} duplicates skipped." if @result.skipped_count > 0
      notice_parts << "#{@result.warnings.count} warning(s)." if @result.warnings.any?
      flash.now[:notice] = notice_parts.join(" ")
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
