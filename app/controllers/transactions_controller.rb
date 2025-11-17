class TransactionsController < ApplicationController
  before_action :set_transaction, only: %i[show edit update destroy]

  def index
    @accounts = current_user.accounts.order(:name)
    @tags = current_user.tags.order(:name)
    @transactions = current_user.transactions.includes(:account, :tags).order(occurred_on: :desc)
    @transactions = @transactions.where(account_id: params[:account_id]) if params[:account_id].present?
    @transactions = @transactions.joins(:tags).where(tags: { id: params[:tag_id] }) if params[:tag_id].present?
  end

  def show; end

  def new
    @transaction = current_user.transactions.build(occurred_on: Date.current, entry_type: :expense)
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
    @tag_totals = current_user.transactions.joins(:tags)
                               .group("tags.id", "tags.name")
                               .count
  end

  private

  def set_transaction
    @transaction = current_user.transactions.find(params[:id])
  end

  def load_form_support
    @accounts = current_user.accounts.order(:name)
    @tag_options = current_user.tags.order(:name)
  end

  def build_transaction
    attrs = transaction_params
    account = current_user.accounts.find(attrs.delete(:account_id))
    attrs.delete(:tag_list)
    current_user.transactions.build(attrs.merge(account: account))
  end

  def transaction_attributes_for_update
    attrs = transaction_params
    attrs.delete(:tag_list)
    attrs[:account] = current_user.accounts.find(attrs.delete(:account_id)) if attrs[:account_id]
    attrs
  end

  def transaction_params
    params.require(:transaction).permit(:account_id, :entry_type, :amount, :occurred_on, :memo, :notes, :status, :tag_list)
  end

  def apply_tags(transaction)
    tag_names = params.dig(:transaction, :tag_list).to_s.split(",").map(&:strip).reject(&:blank?)
    tags = tag_names.map do |name|
      current_user.tags.find_or_create_by!(name: name, slug: name.parameterize)
    end
    transaction.tags = tags
  end
end
