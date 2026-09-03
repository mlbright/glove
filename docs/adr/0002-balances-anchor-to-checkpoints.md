# 2. Balances anchor to checkpoints, not to a synthetic opening transaction

Date: 2026-09-03

## Status

Accepted

## Context

Reported balances disagreed with the bank. The assumption was that transactions
predating diligent importing had never been entered, and that the fix was a way
to record an account's starting amount at a date.

The data says otherwise, mostly. Every account holds at least one transaction in
every calendar month between its first and its last: there are no gaps, and no
missing period to backfill. What exists instead is four separate defects, two of
them pulling in opposite directions.

The PC Financial Mastercard has no opening balance at all. Payments of
$138,995.58 stand against charges of $128,213.69, so the ledger claims the card
is $10,781.89 in credit — impossible for a credit card, and the arithmetic of an
account whose payments settle debts incurred before its first recorded row. Here
the original assumption was exactly right.

The three TD accounts have the opposite problem. Each received a synthetic
"Opening Balance" row when it was empty, standing in for everything prior, dated
just before the earliest row then known. Older history was imported afterwards,
behind that anchor: 116 rows on personal chequing, 210 on joint chequing, 46 on
joint savings now predate the transaction that was created to represent them.
The stand-in and the thing it stands in for are both counted. On joint savings
the anchor, $15,372.43, exceeds the account's entire reported balance.

The personal VISA carries 45 excess rows across 17 groups, worth $1,205.94 —
close to seven eighths of that card's apparent debt. They arrived through four
overlapping re-imports whose dates match the duplicate clusters exactly; a $1.06
conversion fee is recorded nine times. Meanwhile the Mastercard shows the
converse failure: because its parser writes no balance, the tiebreak that lets a
genuine repeat charge through can never engage, and 2,709 transactions across
twenty months contain no same-day identical pair at all. Legitimate second
purchases are being discarded as duplicates.

Two design choices produce all four. The opening balance is a transaction summed
alongside the rest, so anything inserted before it silently invalidates it
without any code being wrong. And an imported row's identity is inferred from
its content, because no export we read carries a transaction id — the TD formats
give date, description, debit, credit and balance; the Mastercard gives
description, type, cardholder, date, time and amount.

## Decision

An account's balance anchors to a checkpoint: an assertion that on a given date
the account closed at a given amount. The balance is that checkpoint plus the
transactions dated strictly after it. Transactions before it remain visible and
searchable but do not contribute.

Checkpoints are end-of-day closing balances, which is the number a statement
already prints, so entering one requires no translation. An opening balance is
simply the earliest checkpoint and a monthly reconciliation is another; there is
one concept, not two.

Consecutive checkpoints are validated against each other. When a checkpoint plus
the transactions following it does not reach the next checkpoint, the difference
is contained within that interval and is reported that way. This is the part
that earns the feature: it converts a balance that is wrong by some amount
somewhere across two years into a discrepancy provably inside one month.

Checkpoints are editable, because a statement misread is entered wrong and must
be correctable. Edits are recorded through the existing revision mechanism.
Nothing else in this system deserves an audit trail more — the balance hangs off
this number, and ADR 1 was written about damage that surfaced later as a balance
nobody could reconstruct. A checkpoint also records whether it was derived by
the importer or verified against a statement by a person; correcting a derived
checkpoint is precisely the act of verifying it, and promotes it.

A mismatch is reported and never repaired silently. The system will offer to
close a gap with a clearly labelled adjustment transaction, but only on an
explicit instruction, and the result is an ordinary visible row that can be
deleted when the real cause is found. An adjustment left stale by a later
checkpoint edit is flagged rather than removed.

Import identity changes with it. Rows are matched by occurrence within their
group: for a given date, amount, description and entry type, a file holding N
such rows and a database holding M of them contributes the occurrences after the
Mth. Two coffees on one day import as two; a re-imported overlapping period
imports nothing. File digest and row number are recorded as provenance, and are
deliberately not part of the matching key.

We considered keeping the opening balance as a transaction and adding an
invariant that it must remain the earliest row. Rejected: it defends against the
failure rather than removing it, and the defence has to hold on every future
path that inserts history. We also considered treating a row's position in its
file as part of its identity, which is the obvious reading of "use the position
to make the record unique". Rejected: statement exports overlap, the same
purchase sits at different offsets in the March and April files, and identity by
position would duplicate every overlap wholesale — the exact mechanism that
produced the VISA's 45 excess rows, generalised.

Uploaded CSVs are retained. ActiveStorage is already installed and holds
nothing.

## Consequences

`Account#balance` stops being a sum over transactions and becomes a sum over a
suffix of them. That is the real price of this decision: the simplest possible
description of a balance is gone, and a reader must now know which checkpoint is
in force before the number means anything.

Balances move, in some cases sharply. Personal chequing reads $3,844.09 and
becomes $191.92, which the overdraft protection fees in its own history make
plausible. Joint chequing rises from $12,711.62 to $13,563.22. Joint savings
falls from $13,432.40 to $4,873.30. The VISA does not move on migration at all,
staying at -$1,471.77, and reaches roughly -$265.83 once its duplicates are
gone (ADR 3 supersedes that last figure with -$325.21, measured rather than
estimated). Each of these is checkable against a statement, and checking them
is the first step of the work rather than the last.

Three of these four figures were first written down a day earlier, before the
rule above had been settled: -$202.69, $15,214.38, $4,870.80 and -$1,401.12.
They were computed as though a transaction dated on the checkpoint's own day
fell outside it. It does not — a checkpoint is an end-of-day closing balance, so
that day's rows are already inside the number and only what follows adds to it.
Joint savings is the clearest case: TD's own balance column closes it at
$15,372.43 on 2025-12-18, and a $2.50 row on 2025-12-19 carries it to
$15,374.93. The earlier arithmetic dropped that $2.50. The VISA's anchor lands
on 2025-06-21 with one row on 2025-06-22 worth -$70.65, which is exactly the
difference between the two figures given for it. The figures above are the ones
the implemented rule produces, verified against a copy of the live database.

The 111 transactions flagged `excludes_from_balance` are all dated on or before
2025-12-10, which places every one of them before its account's checkpoint. They
therefore stop affecting any balance, and whatever was intended by that flag in
late 2025 no longer needs answering to get the numbers right. The column keeps
its unresolved meaning; this decision deliberately does not settle it, and it
would matter again to anyone summing transactions over a historical window.

The four existing "Opening Balance" rows migrate to checkpoints dated to the end
of the preceding day, since each was computed as the balance before its first
imported row. They are marked derived rather than verified: they came from TD's
own balance column and are probably right, but nobody has yet held one against a
statement.

The Mastercard is anchored to its most recent statement, which ends the
$10,781.89 fiction and, incidentally, makes its historical dedupe losses
irrelevant — twenty months of possibly under-counted history now sit before the
checkpoint and no longer bear on the balance. The under-count is real and is
fixed for future imports; it is simply no longer worth reconstructing.

The VISA cannot be repaired in place. Its duplicates are real rows that the new
matching rule would have prevented but does not retroactively remove, and the
source files are gone: the blob tables are empty and no CSV was ever kept. That
account is rebuilt from re-downloaded statements, and the impossibility of doing
this for any other account is why retention is part of this decision rather than
a later improvement.

Deleting an account's last remaining checkpoint returns it to summing every
transaction, with a warning. This is the pre-checkpoint behaviour and it is
wrong in the ways described above, but refusing the deletion outright would
leave an account permanently hostage to a checkpoint entered in error.
