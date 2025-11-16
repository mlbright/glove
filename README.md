# Fearless Finance

A single-tenant Ruby on Rails application for tracking income and expenses, managing multiple accounts, recurring schedules, tag clouds, and CSV imports. Authentication is powered by OAuth (Google or GitHub), so no passwords are stored.

## Prerequisites

- Ruby 3.4+
- Node.js 18+ (for Tailwind builds)
- SQLite (default) or another Rails-supported database

## Setup

```bash
bundle install
rails db:setup
```

Configure OAuth credentials via environment variables (e.g. `.env`).

```
GOOGLE_CLIENT_ID=xxxx
GOOGLE_CLIENT_SECRET=xxxx
GITHUB_CLIENT_ID=xxxx
GITHUB_CLIENT_SECRET=xxxx
```

## Running the app

```bash
bin/dev
```

This starts Rails, Tailwind, and esbuild via Foreman. Sign in with Google or GitHub to reach the dashboard.

## Test suite

```bash
bundle exec rspec
```

The suite covers models, request flows, and the CSV importer service.

## Features

- **Dashboard** summarizing total income, expenses, account balances, and upcoming schedules.
- **Transactions** with CRUD UI, per-account scoping, tag cloud, status tracking, audit trail, and optional linkage to schedules or imports.
- **Schedules** define recurring cadence (daily/weekly/monthly) with next-occurrence tracking.
- **Accounts** support multiple financial sources (checking, savings, credit card, etc.).
- **Tags** with automatic slugging and aggregated cloud view.
- **Bulk CSV import** using saved templates to map columns to transaction attributes; results logged per batch with audit history.
- **OAuth authentication** via Google or GitHub with Devise + OmniAuth.

## Bulk import workflow

1. Create an Import Template specifying CSV delimiter, headers, and column mappings (e.g., `Amount → amount`, `Category → tag_list`).
2. Upload a CSV file in a new Import Batch and start the import.
3. Monitor completion status, processed/failed counts, and error notes from the batch detail view.

## Audit logging

Every transaction create/update/destroy writes a `TransactionRevision` with a timestamped change log for traceability.

## Accessibility & Security

- All controllers enforce `current_user` scoping.
- Devise handles session management; only OAuth sign-in is allowed.
- CSRF protection is enabled throughout.
