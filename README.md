# budget-app

[![Build status](https://github.com/MalachiF18/budget-app/actions/workflows/ci.yml/badge.svg)](https://github.com/MalachiF18/budget-app/actions/workflows/ci.yml)

A phone app with two halves:

- **Personal**: plan your month. Enter your pay, necessary bills, a savings
  target, subscriptions and one-time needs, and see what's left to spend.
- **Group**: split costs with friends. Join a group with a sync code, log what
  you paid for the group, and see at a glance what you owe each person and what
  they owe you.

CSC 4330 Project 5. Due **Fri 10/23, 5:00 pm**.

- Task board: Trello "4330 Project 5". Start with the **READ ME** card at the top of To Do.
- Mockup of both screens: https://claude.ai/artifact/RntynznWRgU1PaJg7Pp4zy (ask Allen for access)

## Stack

| Part | Choice |
|---|---|
| App | Flutter (Android first) |
| Server | Supabase: sign-in, Postgres database, file storage for receipts, live updates |
| Automated build | GitHub Actions: format, analyze, test, build APK on every PR |

**Money is always stored and computed as whole cents (`int`), never `double`.**
`$12.34` is `1234`. Convert to dollars only when displaying.

## Who works where

Each person owns one folder, so we don't edit the same files.

```
lib/
  main.dart            app start, bottom nav (Personal | Group)
  core/                shared: themes, money formatting, Supabase client   (Allen)
  features/
    personal/          personal budget screen, math, edit sheets           (Malachi)
    group/             groups, join by code, expenses, ledger, receipts    (Davante)
    balances/          split math, who-owes-whom, recording payments       (4th member)
test/                  mirrors lib/, one test file per logic file
supabase/migrations/   database tables and security rules                  (Allen)
docs/                  architecture diagram
```

Need to change a file outside your folder? Say so in the group chat first.

## Screens

**Personal.** Period toggle W / M / Y (M by default). Status line "You're doing
WELL" in green or "You're doing BAD" in red. Cards, each with a progress bar,
tap to edit:

1. Your earnings: expected monthly pay
2. Necessary bills: rent, utilities, cell plan…
3. Savings target: a fixed amount **or** a % of what's left after bills
4. Subscriptions: streaming, music…
5. One-time needs: extras for this month
6. Spending money: the bottom line, calculated, not editable

`Spending money = earnings − bills − savings − subscriptions − one-time needs − logged spending`

**Group.** Its own color theme, same style as Personal. Period toggle W / M / ALL
(ALL by default). Sync code to share, total spent, and a card per member showing
what they spent, **what you owe them** and **what they owe you**. Tap a card to
see their ledger.

## Group rules

- **Joining:** a long alphanumeric sync code, checked by the server.
- **Adding an expense:** description, amount, date (fills in today, can be
  changed), optional receipt photo. Pick who is charged; Select all / Deselect
  all, **nobody selected by default**. "Share with me" is **on by default**.
  - Bought for one person with "Share with me" off: a direct charge to them.
  - Shared: split evenly among everyone included. Leftover cents go to the
    first people so the shares always add up to the total.
- **Editing:** only the person who added an expense can edit or delete it.
- **Paying back:** only the person who **received** money can record a payment.
  The payer can't mark a debt off someone else's ledger, so it can't be faked.

## Data

| Table | Holds |
|---|---|
| `profiles` | display name per user |
| `budgets`, `budget_items`, `transactions` | personal budget; only its owner can read it |
| `groups`, `group_members` | groups and sync codes |
| `expenses`, `expense_shares` | who paid, how much, who is charged how much |
| `payments` | money received, recorded by the receiver |

The rules above are enforced by the database (row-level security), not only by
the app.

## Run it

```
flutter pub get   # install dependencies
flutter test      # run the tests
flutter run       # launch on a connected device or emulator
```

The Supabase URL and publishable key (card 1.3) are passed at build time with
`--dart-define`; never commit the service-role key.

## How we work

1. Take a card from your list whose **Needs first** cards are done. Move it to **Doing**.
2. Branch off `main`, named after the card: `2.3-personal-screen`.
3. Write the test first for anything that calculates.
4. Open a PR into `main`. The automated build must pass before merging.
5. When the card's **Done when** is true and the PR is merged, move it to **Done**.

Commit small and often; regular progress is part of the grade.
