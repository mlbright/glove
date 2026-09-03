# frozen_string_literal: true

namespace :balances do
  desc "Report rows an account's balance column proves cannot exist. APPLY=1 removes them."
  task :collapse, [ :account ] => :environment do |_task, args|
    name = args[:account] or abort "Usage: rails 'balances:collapse[Account Name]' [APPLY=1]"
    account = Account.find_by(name: name) or abort "No account named #{name.inspect}"

    collapse = Transactions::BalanceCollapse.new(account)
    result = collapse.plan

    puts "#{account.name}: #{account.transactions.count} rows"
    if result.groups.empty?
      puts "Nothing to collapse."
      next
    end

    result.groups.each do |group|
      puts format("  %-46s x%d  balance %.2f  discard %d",
                  group.label[0, 46], group.discarded_count + 1,
                  group.balance_cents / 100.0, group.discarded_count)
    end
    puts format("%d rows in %d groups; ledger moves by %+.2f",
                result.removed_count, result.groups.size, result.ledger_change_cents / 100.0)

    # Reported, never repaired without an explicit instruction. See docs/adr/0002.
    unless ENV["APPLY"] == "1"
      puts "Dry run. Re-run with APPLY=1 to remove them."
      next
    end

    actor = User.find_by(email: ENV["ACTOR_EMAIL"]) if ENV["ACTOR_EMAIL"].present?
    applied = collapse.apply!(acted_by: actor)
    puts "Removed #{applied.removed_count} rows; #{account.transactions.reload.count} remain."
    puts "Each removal is recorded as a destroy revision."
  end
end
