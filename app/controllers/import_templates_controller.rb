class ImportTemplatesController < ApplicationController
  before_action :set_template, only: %i[show edit update destroy]

  def index
    @import_templates = current_user.import_templates.order(:name)
  end

  def show; end

  def new
    @import_template = current_user.import_templates.build
    @mapping_rows = default_mapping_rows
  end

  def edit
    @mapping_rows = build_rows_from_template(@import_template)
  end

  def create
    @import_template = current_user.import_templates.build(template_attributes)
    @mapping_rows = build_rows_from_template(@import_template)

    if @import_template.save
      redirect_to @import_template, notice: "Template created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    @import_template.assign_attributes(template_attributes)
    @mapping_rows = build_rows_from_template(@import_template)

    if @import_template.save
      redirect_to @import_template, notice: "Template updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @import_template.destroy
    redirect_to import_templates_path, notice: "Template deleted."
  end

  private

  def set_template
    @import_template = current_user.import_templates.find(params[:id])
  end

  def template_params
    params.require(:import_template).permit(:name, :delimiter, :header, :column_examples, mapping_rows: %i[column attribute])
  end

  def template_attributes
    attrs = template_params.to_h
    attrs[:column_examples] = attrs[:column_examples].to_s.lines.map(&:strip).reject(&:blank?)
    mapping = Array(attrs.delete("mapping_rows"))
    attrs[:mapping] = mapping.each_with_object({}) do |row, hash|
      column = (row[:column] || row["column"]).to_s.strip
      attribute = (row[:attribute] || row["attribute"]).to_s.strip
      next if column.blank? || attribute.blank?

      hash[column] = attribute
    end
    attrs
  end

  def build_rows_from_template(template)
    rows = template.mapping.presence || {}
    if rows.empty?
      default_mapping_rows
    else
      rows.map { |column, attribute| { column: column, attribute: attribute } }
    end
  end

  def default_mapping_rows
    Array.new(5) { { column: nil, attribute: nil } }
  end
end
