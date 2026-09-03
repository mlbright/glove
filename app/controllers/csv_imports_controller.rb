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
    csv_import = retain(account, params[:csv_file], file_content)

    importer = CsvImports::Importer.new(
      user: current_user,
      account: account,
      import_format: account.import_format,
      csv_import: csv_import
    )
    @result = importer.import(file_content)
    @account = account
    @csv_import = csv_import
    # The balance reported against the file is no longer a single whole-account
    # number: the checkpoints an account holds localise any difference to the
    # interval that contains it. See docs/adr/0002.
    @audit = Checkpoints::Audit.new(account.reload)

    if quiet_success?
      flash[:notice] = "Successfully imported #{@result.imported_count} transactions."
      redirect_to transactions_path
    elsif @result.error_count.zero?
      flash.now[:notice] = success_notice
      render :result
    else
      flash.now[:alert] = "Import completed with errors."
      render :result, status: :unprocessable_entity
    end
  rescue StandardError => e
    flash.now[:alert] = "Import failed: #{e.message}"
    render :new, status: :unprocessable_entity
  end

  private

  def quiet_success?
    @result.error_count.zero? &&
      @result.skipped_duplicates.empty? &&
      @result.derived_checkpoint.nil? &&
      @result.suggested_checkpoint.nil? &&
      @audit.balanced?
  end

  def success_notice
    parts = [ "Successfully imported #{@result.imported_count} transactions." ]
    parts << "#{@result.skipped_count} rows already held." if @result.skipped_count.positive?
    parts << "#{@audit.discrepancies.count} interval(s) do not balance." unless @audit.balanced?
    parts.join(" ")
  end

  # Uploaded CSVs are retained. The personal VISA could not be repaired in place
  # because its source files were gone; keeping the file is what makes the same
  # repair possible next time. See docs/adr/0002.
  def retain(account, upload, content)
    csv_import = CsvImport.new(
      account: account,
      user: current_user,
      filename: upload.original_filename,
      digest: CsvImport.digest_for(content)
    )
    csv_import.file.attach(
      io: StringIO.new(content),
      filename: upload.original_filename,
      content_type: upload.content_type.presence || "text/csv"
    )
    csv_import.save!
    csv_import
  end
end
