class SchedulesController < ApplicationController
  before_action :set_schedule, only: %i[show edit update destroy]

  def index
    @schedules = current_user.schedules.order(:next_occurs_on)
  end

  def show; end

  def new
    @schedule = current_user.schedules.build(next_occurs_on: Date.current)
    load_support
  end

  def edit
    load_support
  end

  def create
    @schedule = current_user.schedules.build(schedule_params)
    if @schedule.save
      redirect_to @schedule, notice: "Schedule created."
    else
      load_support
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @schedule.update(schedule_params)
      redirect_to @schedule, notice: "Schedule updated."
    else
      load_support
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @schedule.update(active: false)
    redirect_to schedules_path, notice: "Schedule deactivated."
  end

  private

  def set_schedule
    @schedule = current_user.schedules.find(params[:id])
  end

  def load_support
    @accounts = current_user.accounts.order(:name)
  end

  def schedule_params
    params.require(:schedule).permit(:account_id, :name, :frequency, :interval_value, :next_occurs_on, :active)
  end
end
