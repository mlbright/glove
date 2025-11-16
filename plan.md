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
