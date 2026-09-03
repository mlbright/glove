# frozen_string_literal: true

class CheckpointsController < ApplicationController
  before_action :set_account, only: %i[new create]
  before_action :set_checkpoint, only: %i[edit update destroy]

  def new
    @checkpoint = @account.checkpoints.build(
      closed_on: params[:closed_on].presence || Date.current,
      balance_cents: params[:balance_cents].presence
    )
  end

  def create
    @checkpoint = @account.checkpoints.build(checkpoint_params)
    # A person entering a closing balance is reading it off a statement, which
    # is what "verified" means. Only the importer derives one.
    @checkpoint.source = :verified
    @checkpoint.acted_by = current_user

    if @checkpoint.save
      redirect_to @account, notice: "Checkpoint recorded. #{@account.name} now reads #{@account.reload.balance.format}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    @checkpoint.assign_attributes(checkpoint_params)
    @checkpoint.acted_by = current_user

    if @checkpoint.save
      redirect_to @checkpoint.account, notice: notice_for_update
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    account = @checkpoint.account
    @checkpoint.acted_by = current_user
    @checkpoint.destroy
    account.reload

    if account.anchored?
      redirect_to account, notice: "Checkpoint deleted."
    else
      # The pre-checkpoint behaviour, and wrong in the ways ADR 2 describes.
      # Refusing the deletion outright would leave an account permanently
      # hostage to a checkpoint entered in error, so it is allowed and said.
      redirect_to account, alert: "Checkpoint deleted. #{account.name} has no checkpoint left, so its balance is now the sum of every transaction it holds — including any history that predates the account's real opening balance."
    end
  end

  private

  def set_account
    @account = Account.find(params[:account_id])
  end

  def set_checkpoint
    @checkpoint = Checkpoint.find(params[:id])
    @account = @checkpoint.account
  end

  def checkpoint_params
    params.require(:checkpoint).permit(:closed_on, :balance)
  end

  def notice_for_update
    stale = Checkpoints::Audit.new(@checkpoint.account.reload).stale_adjustments
    notice = "Checkpoint updated."
    return notice if stale.empty?

    # Flagged rather than removed: the adjustment is a real row someone asked
    # for, and deciding what to do with it is theirs.
    notice + " #{stale.count} balance adjustment#{'s' if stale.count > 1} no longer close the gap they were made for and are flagged below."
  end
end
