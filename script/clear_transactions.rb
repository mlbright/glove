#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to delete all transactions from the database
# Usage: bin/rails runner script/clear_transactions.rb

require_relative "../config/environment"

puts "WARNING: This will delete ALL transactions and related records!"
puts "Transaction count: #{Transaction.count}"
puts "TransactionRevision count: #{TransactionRevision.count}"
puts "TransactionTag count: #{TransactionTag.count}"
puts ""

if ARGV.include?("--force") || ARGV.include?("-f")
  confirm = "yes"
else
  print "Type 'yes' to confirm: "
  confirm = $stdin.gets&.chomp
end

if confirm == "yes"
  ActiveRecord::Base.transaction do
    TransactionRevision.delete_all
    TransactionTag.delete_all
    Transaction.delete_all
  end

  puts "Done! All transactions cleared."
  puts "Remaining transactions: #{Transaction.count}"
else
  puts "Aborted."
end
