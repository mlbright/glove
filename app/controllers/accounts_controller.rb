class AccountsController < ApplicationController
  before_action :set_account, only: %i[show edit update destroy]

  def index
    @accounts = current_user.accounts.order(:name)
  end

  def show; end

  def new
    @account = current_user.accounts.build
  end

  def edit; end

  def create
    @account = current_user.accounts.build(account_params)
    if @account.save
      redirect_to @account, notice: "Account created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @account.update(account_params)
      redirect_to @account, notice: "Account updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @account.update(archived_at: Time.current)
    redirect_to accounts_path, notice: "Account archived."
  end

  private

  def set_account
    @account = current_user.accounts.find(params[:id])
  end

  def account_params
    params.require(:account).permit(:name, :account_type, :color, :description)
  end
end
