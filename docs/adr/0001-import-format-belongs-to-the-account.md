# 1. Import format is a property of the account, not a choice at import time

Date: 2026-08-30

## Status

Accepted

## Context

The CSV import page asked for two things independently: an account, and an
import format. Nothing connected them. The server checked only that the
submitted format was one of the three it knew about — never that it suited the
chosen account.

The failure this invites is quiet. Every supported format is a list of dates,
descriptions and amounts; run a TD Visa export through the chequing parser and
the rows still parse, but dates land in the wrong order, debits and credits swap
meaning, and balance reconciliation compares numbers that were never comparable.
The import reports success. The damage surfaces later, as a balance that has
drifted for reasons nobody can reconstruct, in an account holding thousands of
transactions.

In practice the choice was never open: each account is fed by exactly one bank
export. The format was already determined by the account — the form just asked
anyway, once per import, forever.

## Decision

An account holds its import format (`accounts.import_format`, nullable). The
import page has no format field. The server derives the format from the chosen
account and does not accept one from the request at all; an account with no
format configured cannot be imported into, and says so.

We considered pre-selecting the format on account choice while leaving it
editable. Rejected: pre-selection shrinks the window for the mistake without
closing it, and the mistake is the kind you don't notice.

## Consequences

A one-off import in a format other than the account's own is no longer possible
from the UI. Changing the account's format is the escape hatch, and is allowed
at any time — the format governs future parses only, so accounts that already
hold transactions can be re-pointed when a bank changes its export.

The set of formats now lives in one place, `CsvImports::Format`, which the
account enum, both forms, and the importer read from. Teaching Glove a new bank
is one edit rather than four, and the edit that used to be forgotten — the one
that makes the format assignable — no longer exists separately.

`import_format` is a string column, against this repo's convention of integer
enums (`entry_type`, `status`). The value is a parser identity shared between
the database and the code, not a display-only status: an integer enum silently
remaps every stored row if the list is ever reordered, and that remap would
repoint thousands of transactions' provenance at the wrong parser.

The `accounts.account_type` column, dead since it was re-added and never read,
was dropped in the same change. It described the kind of account, which is
adjacent enough to import format to confuse a future reader about which one
decides the parser — and TD chequing and TD savings prove the two are not the
same axis, being different kinds of account with the same export.

The Stimulus controller that reveals the format on the import page is not
covered by tests: this repo has no system-spec infrastructure, and standing it
up for one presentational binding costs more than the binding is worth. It is
presentational precisely because the server ignores the client on this question
— if it stops firing, imports remain correct and the format line goes blank.
