class ImportBatchesController < ApplicationController
  before_action :set_batch, only: %i[show start]

  def index
    @import_batches = current_user.import_batches.includes(:import_template).order(created_at: :desc)
  end

  def show; end

  def new
    @import_batch = current_user.import_batches.build
    load_templates
  end

  def create
    @import_batch = current_user.import_batches.build(batch_params)

    if @import_batch.save
      @import_batch.update(source_filename: @import_batch.csv_file.filename.to_s)
      redirect_to start_import_batch_path(@import_batch)
    else
      load_templates
      render :new, status: :unprocessable_entity
    end
  end

  def start
    unless @import_batch.pending?
      return redirect_to @import_batch, alert: "Batch has already been processed."
    end

    Transactions::Importer.new(@import_batch).call
    redirect_to @import_batch, notice: "Import finished with #{@import_batch.processed_count} processed and #{@import_batch.failed_count} failed."
  end

  private

  def set_batch
    @import_batch = current_user.import_batches.find(params[:id])
  end

  def load_templates
    @templates = current_user.import_templates.order(:name)
  end

  def batch_params
    params.require(:import_batch).permit(:import_template_id, :csv_file)
  end
end
