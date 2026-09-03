# 3. Imported balances are audited row by row, not only between checkpoints

Date: 2026-09-03

## Status

Proposed

## Context

Two of the three formats Glove reads carry a running balance against every row.
`CsvImports::Format` already records this as `reconciles_balance`, true for
`td_chequing` and `td_visa` and false for the PC Financial Mastercard, whose
export gives description, type, cardholder, date, time and amount and nothing
else.

ADR 2 spends that column at exactly two points, both of which read a single row:
`derive_opening_checkpoint` undoes the earliest row's own effect to find the
balance standing before it, and `suggest_closing_checkpoint` offers the balance
printed against the latest. Everything between is ignored.

The column asserts far more than those two numbers. Between any two consecutive
rows carrying a balance, the bank is stating an equation:

    balance(N) - balance(N-1) == signed_amount(N)

Every row the file contains is therefore checkable against its neighbour, using
nothing but data already stored. Where the checkpoint audit of ADR 2 confines a
discrepancy to the interval between two statements, this confines it to the gap
between two rows.

That equation was tested against a copy of the live database, never the file
itself. On the three TD deposit accounts it holds on all 662 adjacent pairs
without a single exception — 228 rows on personal chequing, 360 on joint
chequing, 77 on joint savings, and 306 of those pairs falling on a shared date.
The bank's arithmetic and Glove's stored `entry_type` and `amount_cents` agree
everywhere.

The personal VISA breaks it 52 times across 902 pairs, and breaks it exactly
where ADR 2 said that account was corrupt. Forty of the 52 violations fall in
February, March and April 2026; 15 of the account's 17 duplicate groups fall in
those same three months. The violations are not scattered noise, and they are
not distributed like a parser defect would be.

The residuals then settle the account's true balance. They sum to $1,146.56.
The VISA's checkpoint anchor is -$1,471.77, and -$1,471.77 + $1,146.56 is
-$325.21 — which is, to the cent, the last balance TD itself printed on that
card, on 2026-08-21. Two routes that share no arithmetic arrive at the same
number.

That figure supersedes an estimate in ADR 2. That decision reasoned that the 45
excess rows are worth $1,205.94 at face value and put the repaired VISA at
roughly -$265.83. The chain says the excess rows' *net* effect is $1,146.56,
$59.38 less, because valuing a duplicate at face assumes it is pure surplus and
some of these sit inside groups the chain reorders rather than inflates.

The same test independently confirms the rest of ADR 2. The last balances TD
printed are $191.92 on personal chequing, $13,563.22 on joint chequing and
$4,873.30 on joint savings, which are the three migrated balances that decision
predicts, reached here by summing nothing at all.

## Decision

For formats where `reconciles_balance` is true, consecutive balance-bearing rows
are audited against the equation above, and a violation is reported against the
pair it falls between.

Only rows carrying a balance take part. A hand-entered row has none, and a row
whose file never printed one is not evidence of anything; the chain suspends at
such a row and resumes at the next row that carries a balance, rather than
reporting a violation it cannot substantiate. The same applies across the join
between two files, where the rows are adjacent in the account but were never
adjacent in any statement.

The audit needs a row order, and the database must supply it, because a date
alone does not: 306 of the passing pairs share a date, and TD stores every row
of a day at local midnight. `transactions.import_row_number`, added by ADR 2, is
that order within a file. ADR 2 deliberately kept the row number out of the
*matching* key, and using it here does not reverse that. Matching asks whether
two rows are the same event, which a position in a file cannot answer because
statements overlap and the same purchase sits at different offsets in the March
and April exports. Ordering asks which of two rows came first in one file, which
is the only question a row number can answer well. Rows predating the column —
which today is all of them — fall back to `(occurred_on, id)`, and that fallback
is why the evidence above could be gathered at all.

A violation is reported and never repaired, which is ADR 2's rule and is not
weakened here. The system does not reorder rows, flip a sign, or delete a
suspected duplicate on its own account. It names two rows, states the residual,
and stops.

This does not replace `Checkpoints::Audit`, and both run. The checkpoint audit
works on every account including the Mastercard, and it catches the failure this
one structurally cannot see: a row missing from the file entirely, at a boundary
where the chain is suspended anyway. The row audit is far finer, but only where
the column exists. They fail in different directions, which is the argument for
keeping both.

We considered dropping checkpoints for the two TD formats and defining the
balance as the last balance-bearing row. Rejected on three counts. It goes stale
the moment a transaction is entered by hand, since that row carries no balance
and the anchor is no longer the latest row. It is silent on the Mastercard,
leaving one account on a different rule than the others for no reason a reader
would guess. And it is derived, in ADR 2's precise sense: it is the file
agreeing with itself, and cannot know that the earliest file on hand does not
reach back to where the account really opened. That last is the defect that let
personal chequing read $3,844.09.

We considered treating a violation as authority to correct the row — flipping an
entry type, or resequencing a day until the chain closes. Rejected: the chain
proves that two adjacent rows disagree, not which of them is wrong, and a repair
chosen by the machine would be indistinguishable afterwards from data the bank
actually sent.

## Consequences

The VISA stops being described by an estimate. Rebuilding it from re-downloaded
statements gains a target — 52 violations, net $1,146.56, concentrated in three
months — and a figure to land on, -$325.21, that TD printed and the chain
derives independently. The estimate of roughly -$265.83 in ADR 2's Consequences
is superseded and should be read as the earlier of two numbers.

The three deposit accounts gain a standing check that passes on every pair
today. Its value is entirely prospective: it is the thing that would have caught
the VISA's four overlapping re-imports in 2026 while they were happening rather
than in an investigation two years later, and occurrence matching now prevents
the specific mechanism but not every future one.

The Mastercard gains nothing at all. It has no balance column, so it keeps only
the checkpoint audit and its single hand-entered anchor. This asymmetry is
inherent in what the banks send and is not worth engineering around; it is worth
stating plainly on the account page, so that a passing row audit on three
accounts is not read as a clean bill of health for the fourth.

The cost is an ordering assumption that the data does not fully justify for
existing rows. Same-day rows have no intrinsic order, and the 306 same-day pairs
pass today because `id` happens to have been assigned in file order during a
single pass of each import. `import_row_number` turns that luck into a guarantee
for everything imported from now on, and cannot retrofit it. A violation on a
same-day pair of historical rows is therefore weaker evidence than one on rows
dated a week apart, and should be reported as such rather than presented with
the same confidence.

A violation names a pair, not a culprit. The row it is reported against is the
later of two, which is a presentational convenience and not a claim about which
row is wrong — as the VISA's near-cancelling residuals show, where $685.62
against one row is followed by -$683.70 against the next and neither row is
individually defective.

Retention from ADR 2 is what makes this durable. The audit reads stored columns,
so it can run at any time, but a violation is only actionable if the file that
produced the rows can still be consulted. The VISA is the account where that is
impossible and also the only account where the audit currently fires.
