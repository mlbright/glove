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

### Checkpoint

An assertion that on a given date an Account closed at a given amount — the
number a statement prints, so entering one requires no translation. An
Account's balance is its latest Checkpoint plus the transactions dated strictly
after it; transactions before it stay visible and searchable but do not
contribute. An account with no Checkpoint falls back to summing everything it
holds.

An opening balance is simply the earliest Checkpoint and a monthly
reconciliation is another: one concept, not two. A Checkpoint is *derived* when
the importer computed it from a bank's own balance column, and *verified* when a
person entered or corrected it against a statement — correcting a derived one is
precisely the act of verifying it, and promotes it. Every edit is recorded as a
Revision.

### Balance Reconciliation

The check of an Account's consecutive Checkpoints against each other. When a
Checkpoint plus the transactions following it does not reach the next
Checkpoint, the difference is contained within that interval and is reported
that way — which turns a balance that is wrong by some amount somewhere across
two years into a discrepancy provably inside one month.

A mismatch is reported and never repaired silently.

### Adjustment

An ordinary, clearly labelled transaction that closes the gap in one
Reconciliation interval. Created only on an explicit instruction, dated on the
Checkpoint it closes against, and deletable like any other row once the real
cause is found. An Adjustment left stale by a later Checkpoint edit is flagged
rather than removed.

### Occurrence Matching

How an imported row's identity is decided, since no export Glove reads carries a
transaction id. Rows are matched by occurrence within their group: for a given
date, amount, description and entry type, a file holding N such rows against an
account holding M contributes the occurrences after the Mth. Two coffees on one
day import as two; a re-imported overlapping period imports nothing.

A file's digest and a row's number within it are recorded as provenance and are
deliberately not part of the key — statement exports overlap, and identity by
position would duplicate every overlap wholesale.

### CSV Import

A retained upload: the file's bytes, its name, its SHA-256 digest, who uploaded
it and when. Transactions carry the CSV Import they came from, so an account can
be rebuilt from its own sources.

### Revision

The audit trail entry recorded on every create, update and destroy of a
Transaction or a Checkpoint, holding what changed and who acted.
