#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to delete all transactions from a specified account
# Usage: bin/rails runner script/delete_account_transactions.rb [ACCOUNT_NAME_OR_ID]
#
# Examples:
#   bin/rails runner script/delete_account_transactions.rb "TD Chequing"
#   bin/rails runner script/delete_account_transactions.rb 1
#   bin/rails runner script/delete_account_transactions.rb "TD Visa" --force

require_relative "../config/environment"

account_identifier = ARGV.find { |arg| !arg.start_with?("-") }

if account_identifier.nil?
  puts "Usage: bin/rails runner script/delete_account_transactions.rb [ACCOUNT_NAME_OR_ID]"
  puts ""
  puts "Available accounts:"
  Account.find_each do |account|
    puts "  #{account.id}: #{account.name} - #{account.transactions.count} transactions"
  end
  exit 1
end

# Find account by ID or name
account = if account_identifier.match?(/^\d+$/)
  Account.find_by(id: account_identifier.to_i)
else
  Account.find_by(name: account_identifier)
end

if account.nil?
  puts "Error: Account '#{account_identifier}' not found."
  puts ""
  puts "Available accounts:"
  Account.find_each do |account|
    puts "  #{account.id}: #{account.name}"
  end
  exit 1
end

transaction_count = account.transactions.count
revision_count = TransactionRevision.joins(:transaction_record).where(transactions: { account_id: account.id }).count
tag_count = TransactionTag.joins(:transaction_record).where(transactions: { account_id: account.id }).count

puts "Account: #{account.name} (ID: #{account.id})"
puts ""
puts "WARNING: This will delete all transactions from this account!"
puts "Transaction count: #{transaction_count}"
puts "TransactionRevision count: #{revision_count}"
puts "TransactionTag count: #{tag_count}"
puts ""

if transaction_count.zero?
  puts "No transactions to delete."
  exit 0
end

if ARGV.include?("--force") || ARGV.include?("-f")
  confirm = "yes"
else
  print "Type 'yes' to confirm: "
  confirm = $stdin.gets&.chomp
end

if confirm == "yes"
  ActiveRecord::Base.transaction do
    transaction_ids = account.transactions.pluck(:id)
    TransactionRevision.where(transaction_id: transaction_ids).delete_all
    TransactionTag.where(transaction_id: transaction_ids).delete_all
    account.transactions.delete_all
  end

  puts "Done! All transactions deleted from '#{account.name}'."
  puts "Remaining transactions in account: #{account.transactions.count}"
else
  puts "Aborted."
end
