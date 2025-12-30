# Glove

A single-tenant Ruby on Rails application for tracking income and expenses, managing multiple accounts, with CSV imports and tag clouds.
Authentication is powered exclusively by Google OAuth, so no passwords are stored but you must have a Google account and Google OAuth credentials.

This project is intended for personal use and highly specific to my own financial profile.
For instance, the CSV import templates are tailored to the export formats of my banks and credit cards.
Feel free to fork and adapt it for your own needs, but keep in mind that you will likely need to customize for your own situation, for example, modifying the CSV import templates to match your own financial institutions.

**Note: Given the personal nature of this app, pull requests and issues will only be addressed if they align with my own use case.**

Because of the sensitivity of financial data, this app is designed to be self-hosted and not publicly accessible.
I run it on my local [Tailscale][tailscale] mesh network and access it via a private domain, without any public exposure to the internet.
Running it on a public network is strongly discouraged at this point.
Use at your own risk.

The name "Glove" is inspired by the idea of customization and fit, much like a glove tailored to one's hand.

Most of the code was written by chatting in Agent mode with Claude Opus 4.5.

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
```

### OAuth credential setup

#### Google (Google Cloud Console)

1. Visit <https://console.cloud.google.com/> and select or create a project.
2. Under **APIs & Services → OAuth consent screen**, choose *External* and add your email as a test user (no verification needed for local use).
3. Navigate to **APIs & Services → Credentials → Create Credentials → OAuth client ID** and select *Web application*.
4. Set **Authorized JavaScript origins** to the host that serves the Rails app (e.g. `http://localhost:3000` or `http://YOUR_HOST:3000`).
5. Add **Authorized redirect URIs** for Devise/OmniAuth callbacks, typically `http://localhost:3000/users/auth/google_oauth2/callback` and any additional host you use on the network.
6. Copy the generated **Client ID** and **Client Secret** into `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`.

Restart `bin/dev` (or reload the environment) after updating the variables so Devise picks up the new credentials.

## Running the app

```bash
bin/dev
```

This starts Rails and Tailwind via Foreman. Sign in with Google to reach the dashboard.

## Test suite

```bash
bundle exec rspec
```

The suite covers models, request flows, and the CSV importer service.

## Features

- **Dashboard** summarizing total income, expenses, account balances, and recent import activity.
- **Transactions** with CRUD UI, per-account scoping, tag cloud, status tracking, audit trail, and optional linkage to import batches.
- **Accounts** support multiple financial sources (checking, savings, credit card, etc.).
- **Tags** with automatic slugging and aggregated cloud view.
- **Bulk CSV import** using saved templates to map columns to transaction attributes; results logged per batch with audit history.
- **OAuth authentication** via Google with Devise + OmniAuth.

## Bulk import workflow

1. Create an Import Template specifying CSV delimiter, headers, and column mappings (e.g., `Amount → amount`, `Category → tag_list`). If your CSV lacks headers, enter column numbers (`1`, `2`, etc.) instead of column names.
2. Upload a CSV file in a new Import Batch and start the import.
3. Monitor completion status, processed/failed counts, and error notes from the batch detail view.

## Audit logging

Every transaction create/update/destroy writes a `TransactionRevision` with a timestamped change log for traceability.

## Accessibility & Security

- Devise handles session management; only OAuth sign-in is allowed.
- CSRF protection is enabled throughout.

[tailscale]: https://tailscale.com/