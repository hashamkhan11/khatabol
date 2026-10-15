# Database (Supabase / PostgreSQL)

All bookkeeping rules live here, in the database. The Flutter app and the
WhatsApp bot only call these functions, so both always follow the same rules.

## Main ideas

- **Balance is never stored.** A party's balance is the sum of its khata lines.
  Positive = they owe us. Negative = we owe them.
- **Nothing is edited or deleted.** A mistake is fixed by cancelling (which adds
  reversing lines) and recording again. `replace_deal` does both in one step.
- **The app can only read tables.** All writes go through the functions below.
- **Profit is real profit:** sale price minus the average cost of the cloth sold,
  plus commission, minus our costs and expenses. Unsold stock is not a loss.

## Functions the app and bot call

| Action | Function |
|---|---|
| Add / edit / archive party | `create_party`, `update_party`, `set_party_archived` |
| Add / edit / archive cloth type | `create_item`, `update_item`, `set_item_archived` |
| Purchase, sale or commission deal | `record_deal` (see comment in the migration for the fields) |
| Cancel or edit a deal | `cancel_deal`, `replace_deal` |
| Payment in / out | `record_payment` |
| Manual correction | `record_adjustment` |
| Cancel a payment or correction | `reverse_entry` |
| Expense | `record_expense`, `cancel_expense` |
| Stock in / out outside a deal (kind: opening, found, other_in, wastage, shortage, own_use, sample, other_out) | `record_stock_adjustment`, `cancel_stock_adjustment` |
| Reports | `party_balances` (view), `khata_lines` (view), `party_statement`, `stock_summary`, `stock_history`, `profit_report` |

## Files

- `migrations/` – the database itself. These are deployed to Supabase.
- `tests/` – tests that run on a local in-memory Postgres (PGlite).
  `tests/auth_stub.sql` imitates Supabase login for tests only; never deploy it.

## Run the tests

```
cd supabase
npm install
npm test
```
