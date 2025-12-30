# Glove - AI Coding Guidelines

## Architecture Overview

Single-tenant Rails 8.1 personal finance tracker using OAuth-only authentication (Google via Devise). This is a **single-user system**—accounts and transactions are global (not user-scoped).

**Core domain models:**
- `User` → authentication only, owns `Tag`s
- `Account` → has many `Transaction`s (no user association)
- `Transaction` → belongs to `Account`, has many `Tag`s (via `TransactionTag`), has many `TransactionRevision`s for audit trail
- Money amounts stored as `_cents` integers via `money-rails` gem; use `monetize :amount_cents` in models

## Key Patterns

### Single-tenant data access
Since this is a single-user system, query models directly:
```ruby
# Correct - single tenant
@accounts = Account.active.order(:name)
@transactions = Transaction.includes(:account, :tags)

# Authentication still required
before_action :authenticate_user!
```

### Transaction audit logging
Transactions auto-record `TransactionRevision` on create/update/destroy via callbacks. Always set `acted_by` before save to track who made the change:
```ruby
@transaction.acted_by = current_user
@transaction.save
```

### Service objects for business logic
Complex operations live in `app/services/`. CSV import uses format-specific parsers in `CsvImports::` namespace:
- `app/services/csv_imports/importer.rb` orchestrates parsing, opening balance creation, and transaction import
- Format parsers (`TdChequingParser`, `TdVisaParser`, `MastercardParser`) return `ParsedRow` data objects with normalized fields

### Money handling
Use `money-rails` conventions. Store cents, access with `amount`:
```ruby
transaction.amount         # => Money object
transaction.amount_cents   # => Integer (for queries)
```

## Development Commands

```bash
bin/dev                    # Start Rails + Tailwind watcher (Procfile.dev)
bundle exec rspec          # Run test suite
bin/ci                     # Full CI: rubocop, bundler-audit, brakeman, importmap audit
bin/rubocop -a             # Auto-fix style issues
```

## Testing Conventions

- RSpec with FactoryBot; factories in `spec/factories/`
- Use `create(:account)`, `create(:transaction, account: account)` patterns
- Request specs use `sign_in user, scope: :user` from Devise helpers
- Transaction factory auto-sets `acted_by` for audit trail

Example pattern:
```ruby
let(:user) { create(:user) }
let!(:account) { create(:account) }

it "creates a transaction" do
  sign_in user, scope: :user
  post transactions_path, params: { transaction: { account_id: account.id, ... } }
end
```

## UI/Frontend Stack

- **Tailwind CSS** with utility-first styling; run `bin/rails tailwindcss:watch` or use `bin/dev`
- **Hotwire** (Turbo + Stimulus) for SPA-like interactions via importmaps
- **Propshaft** for asset pipeline (not Sprockets)
- Views in `app/views/` use ERB; forms are standard Rails form helpers

## Database

SQLite by default. Accounts use soft-delete (`archived_at` timestamp); use `.active` scope:
```ruby
Account.active  # excludes archived
```

## Adding CSV Import Formats

1. Create parser in `app/services/csv_imports/` following existing patterns (e.g., `TdChequingParser`)
2. Return `Result.new(rows:, errors:)` where rows are `ParsedRow` data objects
3. Register format in `CsvImports::Importer::ACCOUNT_FORMATS`
4. Add to `CsvImportsController::SUPPORTED_FORMATS` for UI dropdown
5. Write spec in `spec/services/csv_imports/`

The importer automatically creates an opening balance transaction when importing to an empty account.
