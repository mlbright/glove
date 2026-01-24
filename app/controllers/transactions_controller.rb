class TransactionsController < ApplicationController
  before_action :set_transaction, only: %i[show edit update destroy]

  def index
    @accounts = Account.order(:name)
    @tags = current_user.tags.order(:name)
    @transactions = Transaction.includes(:account, :tags).order(occurred_on: :desc)
    @transactions = @transactions.where(account_id: params[:account_id]) if params[:account_id].present?
    @transactions = @transactions.joins(:tags).where(tags: { id: params[:tag_id] }) if params[:tag_id].present?
    @transactions = @transactions.where(entry_type: params[:entry_type]) if params[:entry_type].present?
  end

  def show; end

  def new
    @transaction = Transaction.new(occurred_on: Time.current, entry_type: :expense)
    load_form_support
  end

  def edit
    load_form_support
  end

  def create
    @transaction = build_transaction
    @transaction.acted_by = current_user

    if @transaction.save
      apply_tags(@transaction)
      redirect_to @transaction, notice: "Transaction recorded."
    else
      load_form_support
      render :new, status: :unprocessable_entity
    end
  end

  def update
    @transaction.assign_attributes(transaction_attributes_for_update)
    @transaction.acted_by = current_user

    if @transaction.save
      apply_tags(@transaction)
      redirect_to @transaction, notice: "Transaction updated."
    else
      load_form_support
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @transaction.acted_by = current_user
    @transaction.destroy
    redirect_to transactions_path, notice: "Transaction removed."
  end

  def tag_cloud
    @tag_totals = Transaction.joins(:tags)
                             .group("tags.id", "tags.name")
                             .count
  end

  private

  def set_transaction
    @transaction = Transaction.find(params[:id])
  end

  def load_form_support
    @accounts = Account.order(:name)
    @tag_options = current_user.tags.order(:name)
  end

  def build_transaction
    attrs = transaction_params
    raise "Account must be selected" if attrs[:account_id].blank?
    account = Account.find(attrs.delete(:account_id))
    attrs.delete(:tag_list)
    account.transactions.build(attrs)
  end

  def transaction_attributes_for_update
    attrs = transaction_params
    raise "Account must be selected" if attrs[:account_id].blank?
    attrs.delete(:tag_list)
    attrs[:account] = Account.find(attrs.delete(:account_id)) if attrs[:account_id]
    attrs
  end

  def transaction_params
    params.require(:transaction).permit(:account_id, :entry_type, :amount, :occurred_on, :description, :notes, :status).tap do |whitelisted|
      whitelisted[:tag_list] = sanitize_tags(params[:transaction][:tag_list]) if params[:transaction][:tag_list]
    end
  end

  def sanitize_tags(raw_tags)
    # Implement strict validation/sanitization here
    raw_tags.split(",").map(&:strip).reject(&:blank?)
  end

  def apply_tags(transaction)
      tag_names = params.dig(:transaction, :tag_list).to_s.split(",").map(&:strip).reject(&:blank?)
      tags = tag_names.map do |name|
        current_user.tags.find_or_create_by!(name: name, slug: name.parameterize)
    end
    transaction.tags = tags
  end
end
