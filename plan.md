# fearless-finance

Write a single-tenant Ruby on Rails web application that tracks income and expenses for an entity.

It should have the following features:

- Allow the user to input, update, view, and delete (CRUD) financial transactions, specifying whether they are income or expenses, the amount, date
- Each item should have a tag cloud for category.
- All transactions are part of an account, and there can be multiple accounts (e.g., checking, savings, credit card).
- Each transaction should have an optional schedule indicating the frequency (e.g., one-time, daily, weekly, monthly) for recurring transactions, or a specific date indicating the next time it will occur.
- Provide a dashboard that summarizes total income, total expenses, and net balance for the user for all accounts.
- Implement user authentication via OAuth to Google or GitHub to ensure that each user's data is private and secure, and to avoid storing passwords.
- Include tests for all functionality.
- Modifications for transactions should be logged with timestamps for audit purposes.
- There should be a bulk import feature that allows the import of csv files containing multiple transactions at once.
  The user should be able to annotate the columns of the csv to match the fields in the application. These formats shoudl be saved for future imports.

## Architectural Notes

- **Models**
  - `User` authenticates via OmniAuth (Google/GitHub), owns many `Account`s, `Transaction`s, `ImportTemplate`s, and `ImportBatch`es.
  - `Account` belongs to `User`, has many `Transaction`s, stores running balance via queries, soft validation for unique names per user.
  - `Transaction` belongs to `Account` and `User`, optionally to `Schedule`, stores `entry_type` enum (income/expense), amount (decimal), occurred_on date, memo, and JSON audit trail.
  - `Schedule` belongs to `User` and optionally to `Account`, stores frequency enum plus `next_occurs_at`, provides service to instantiate next transaction occurrences.
  - `Tag` belongs to `User`; `TransactionTag` join table connects `Transaction`s and `Tag`s.
  - `ImportTemplate` belongs to `User`, stores column-to-attribute mapping metadata (JSON) and delimiter info.
  - `ImportBatch` belongs to `User` and `ImportTemplate`, tracks uploaded CSV (ActiveStorage) and import results summary; creates `Transaction`s via service.
  - `TransactionRevision` (audit log) captures prior/new values whenever a transaction changes.

- **Controllers / UI**
  - Dashboard controller summarizing totals + per-account net.
  - Accounts controller for CRUD.
  - Transactions controller with Turbo frames for list/form, tag entry widget using Stimulus/Tagify.
  - Schedules controller for managing recurring definitions + preview next run.
  - Import templates controller + Import batches controller for upload/annotation workflow.

- **Key Services**
  - `Transactions::AuditLogger` for capturing revision records.
  - `Transactions::Importer` to map CSV rows → transactions, reusing saved template mapping.
  - `Schedules::Advancer` to compute next dates and instantiate future transactions.

- **Security & Auth**
  - OmniAuth w/ Google & GitHub. Sessions controller handles callback; user email must match allowed domain list (configurable).
  - All controllers scoped via `current_user` before_action.

- **Testing**
  - RSpec + FactoryBot, system tests via Capybara.
  - Service specs for importer, schedule advancer, audit logging.

- **Additional Notes**
  - Tag cloud rendered via aggregated counts per tag for current user.
  - Bulk import page guides user through uploading CSV, mapping columns with JS, and saving template for later reuse.
  - Background job (ActiveJob) imports rows asynchronously for durability; tests cover job behavior using inline adapter for simplicity.
