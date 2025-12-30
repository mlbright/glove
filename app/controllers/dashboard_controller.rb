class DashboardController < ApplicationController
  def index
    @accounts = Account.active.includes(:transactions)
    @recent_transactions = Transaction.joins(:account).merge(Account.active).order(occurred_on: :desc).limit(10)

    active_transactions = Transaction.joins(:account).merge(Account.active)
    @total_income = Money.new(active_transactions.income.sum(:amount_cents), :cad)
    @total_expenses = Money.new(active_transactions.expenses.sum(:amount_cents), :cad)
    @net_total = @total_income - @total_expenses
  end
end
