class DashboardController < ApplicationController
  def index
    @accounts = current_user.accounts.includes(:transactions)
    @recent_transactions = current_user.transactions.order(occurred_on: :desc).limit(10)
    @recent_import_batches = current_user.import_batches.includes(:import_template).order(created_at: :desc).limit(5)
    @import_templates = current_user.import_templates.order(:name)

    totals = current_user.transactions.group(:entry_type).sum(:amount)
    @total_income = totals.fetch(Transaction.entry_types[:income], 0)
    @total_expenses = totals.fetch(Transaction.entry_types[:expense], 0)
    @net_total = @total_income - @total_expenses
  end
end
