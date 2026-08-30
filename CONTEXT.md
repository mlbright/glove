# Context

Glove is a personal ledger: it holds transactions across a handful of real bank
accounts, most of them arriving by CSV export rather than typed in by hand.

## Glossary

### Account

A real-world account whose transactions Glove tracks — a chequing account, a
savings account, a credit card. Accounts are archived rather than deleted, so
their history survives. An account has exactly one Import Format, or none.

### Import Format

The shape of CSV a bank exports for a given account: which columns it has, how
it writes dates, whether it carries a running balance. An Import Format is a
property of the Account, not something chosen per import — selecting an account
settles which Parser reads its file. An account with no Import Format is one
Glove has no way to read files for, and cannot be imported into.

Not every account has one: an account whose transactions are entered by hand
has no bank export behind it.

### Parser

Turns one Import Format's CSV text into rows Glove understands. Each Import
Format has exactly one Parser, and a Parser is meaningless applied to any other
format's file — the same columns mean different things bank to bank, so the
wrong Parser produces plausible-looking wrong transactions rather than an error.

### Balance Reconciliation

The check Glove performs when an Import Format's rows carry the account balance
as of each transaction. Glove replays the imported rows against what it already
holds, records the running balance on each transaction, and warns when the
balance the bank reports disagrees with the balance Glove has computed — the
signal that something is missing or duplicated in the ledger.

Not every Import Format supports it: a format whose rows carry only an amount
has nothing to reconcile against.

### Duplicate

An imported row matching a transaction the account already holds on date,
amount, description, and entry type. Statement exports overlap, so re-importing
an overlapping period is normal and duplicates are skipped rather than treated
as errors.

### Opening Balance

A synthetic transaction Glove creates when importing into an account with no
history, standing in for everything that happened before the first imported row.
Without it the account's balance would only reflect the period covered by the
CSV.
