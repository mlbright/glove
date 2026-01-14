class DashboardController < ApplicationController
  def index
    @accounts = Account.active.includes(:transactions)
    @recent_transactions = Transaction.joins(:account).merge(Account.active).order(occurred_on: :desc).limit(10)
    @net_balance = @accounts.sum(&:balance)
  end
end
