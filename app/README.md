# KhataBol app

Flutter app for the KhataBol ledger. It reads from Supabase and writes only
through the ledger functions in [`../supabase`](../supabase), so the app and the
WhatsApp bot always agree on every balance.

## Screens

| Tab | What it does |
|---|---|
| **Khata** | Every party with their balance (owes you / you owe), totals to receive and to pay, search and filters. A party's page shows the running statement, money received or paid, corrections and cancellations. |
| **Deals** | Purchases, sales and commission deals. The form shows, before saving, how each party's khata will change. Deals can be edited (cancel and re-record) or cancelled. |
| **Stock** | Kg in hand and value for each cloth type, using average cost. Opening stock and wastage adjustments. |
| **Expenses** | Business costs that belong to no deal: rent, salary, tea. Paid in cash or owed to a party. |
| **Profit** | Sales − cost of cloth sold + commission − costs, for any date range. |

## Structure

```
lib/
  config.dart              Supabase URL and publishable key
  data/models.dart         typed rows from tables, views and report functions
  data/deal_draft.dart     the deal form state, validation and khata preview
  data/ledger_repository.dart  every Supabase read and RPC call
  ui/common.dart           shared widgets: async loading, pickers, dialogs
  screens/                 one file per screen
test/                      unit tests
```

Mistakes are never edited in place. Cancelling a deal, payment or expense adds
reversing lines, so the statement keeps a full history.

## Running

Requires Flutter 3.38+.

```
flutter pub get
flutter run -d chrome     # or an Android device
```

The app connects to the project in `lib/config.dart`. To use another Supabase
project, apply the migrations there and pass its details:

```
flutter run --dart-define=SUPABASE_URL=https://xyz.supabase.co --dart-define=SUPABASE_KEY=sb_publishable_...
```

The publishable key is safe in a client: row-level security limits each user to
their own rows and allows no direct writes.

Sign-in is by email and password. Accounts are created by the owner in the
Supabase dashboard; the app has no public sign-up.

## Tests

```
flutter analyze
flutter test
```
