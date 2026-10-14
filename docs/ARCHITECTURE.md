# Architecture

Trello card 1.9. For the table details and security rules see
[DATABASE.md](DATABASE.md).

## Overview

The phone app is Flutter. It has no server code of its own. It talks straight to
Supabase, which gives us anonymous sign-in, a Postgres database, file storage for
receipt photos, and live updates. The security rules live in the database
(row-level security, RLS), so a modified app still cannot read or write what it
should not. Every write to a group goes through a database function (RPC) that
checks who is calling. GitHub Actions builds the APK on every pull request.

## 1. Big picture

```mermaid
flowchart LR
  subgraph Phone["Phone app (Flutter)"]
    Personal["Personal screen"]
    Group["Group screen"]
    Core["core: money, theme, Supabase client"]
    Personal --> Core
    Group --> Core
  end

  subgraph Supabase
    Auth["Auth: anonymous sign-in"]
    DB[("Postgres with RLS")]
    RPC["RPC functions"]
    Storage["Storage: receipts bucket"]
    RT["Realtime: expenses + payments"]
    RPC --> DB
    DB --> RT
  end

  CI["GitHub Actions CI: builds the APK"]

  Core -->|sign in| Auth
  Core -->|"read tables (RLS filtered)"| DB
  Core -->|"group writes"| RPC
  Core -->|"upload / view photos"| Storage
  RT -->|"change events"| Core
  CI -.->|"builds from the repo"| Phone
```

Personal budget tables (`budgets`, `budget_items`, `transactions`) are the one
exception to "writes go through RPCs": the owner writes them directly, and RLS
allows only the owner.

## 2. Tables

Key columns only. Money columns end in `_cents` (whole cents, `bigint`).
`AUTH_USERS` is Supabase's own `auth.users` table.

```mermaid
erDiagram
  AUTH_USERS ||--o| profiles : "id"
  AUTH_USERS ||--o| budgets : "user_id"
  AUTH_USERS ||--o{ transactions : "user_id"
  AUTH_USERS ||--o{ join_attempts : "user_id"
  budgets ||--o{ budget_items : "budget_id"
  profiles ||--o{ groups : "created_by"
  groups ||--o{ group_members : "group_id"
  profiles ||--o{ group_members : "user_id"
  groups ||--o{ expenses : "group_id"
  group_members ||--o{ expenses : "paid_by, created_by"
  expenses ||--o{ expense_shares : "expense_id"
  profiles ||--o{ expense_shares : "user_id"
  groups ||--o{ payments : "group_id"
  group_members ||--o{ payments : "from_user, to_user"

  AUTH_USERS {
    uuid id PK
  }
  profiles {
    uuid id PK
  }
  budgets {
    uuid id PK
    uuid user_id FK
    bigint earnings_cents
    bigint savings_value
  }
  budget_items {
    uuid id PK
    uuid budget_id FK
    bigint amount_cents
  }
  transactions {
    uuid id PK
    uuid user_id FK
    bigint amount_cents
  }
  join_attempts {
    bigint id PK
    uuid user_id FK
  }
  groups {
    uuid id PK
    text sync_code
    uuid created_by FK
  }
  group_members {
    uuid group_id PK, FK
    uuid user_id PK, FK
  }
  expenses {
    uuid id PK
    uuid group_id FK
    uuid paid_by FK
    uuid created_by FK
    bigint amount_cents
    text receipt_path
  }
  expense_shares {
    uuid expense_id PK, FK
    uuid user_id PK, FK
    bigint share_cents
  }
  payments {
    uuid id PK
    uuid group_id FK
    uuid from_user FK
    uuid to_user FK
    uuid recorded_by FK
    bigint amount_cents
  }
```

`paid_by`, `created_by`, `from_user` and `to_user` point at `group_members`
together with `group_id`, so the database itself refuses someone who is not in
the group. `recorded_by` also points at `profiles`, and a check forces it to
equal `to_user`.

## 3. Add a shared expense

```mermaid
sequenceDiagram
  participant A as Phone A (payer)
  participant S as Supabase
  participant B as Phone B (other member)

  A->>S: rpc add_expense(group, description, amount_cents, shares)
  S->>S: is_group_member? (caller from sign-in, not an argument)
  S->>S: validate_expense_shares checks shares add up to amount_cents
  S->>S: insert expenses row, insert expense_shares rows
  S-->>A: new expense id
  S-)B: Realtime event on expenses (members only)
  B->>S: refetch expenses and shares (RLS filtered)
  S-->>B: current rows
```

The app does the even split (leftover cents to the first people) and sends the
result. The database only checks that it adds up. Realtime does not carry the
data we show, only the signal to refetch.

## 4. Paying someone back

```mermaid
sequenceDiagram
  participant P as Phone P (payer)
  participant R as Phone R (receiver)
  participant S as Supabase

  P->>R: hands over the money (outside the app)
  R->>S: rpc record_payment(group, from_user = P, amount_cents)
  S->>S: caller R is a group member, from_user is not R
  S->>S: insert payments with to_user = recorded_by = R
  S-->>R: new payment id
  S-)P: Realtime event on payments
  P->>S: refetch balances
```

`record_payment` has no argument for the receiver. It always uses the caller, so
the payer cannot record their own payment. Clients also have no direct insert
permission on `payments`, and the table's check `recorded_by = to_user` backs
this up.

## Who owns which folder

| Folder | Owner |
|---|---|
| `lib/core/` (themes, money, Supabase client) | Allen |
| `lib/features/personal/` | Malachi |
| `lib/features/group/` | Davante |
| `lib/features/balances/` | 4th member |
| `supabase/migrations/` | Allen |
| `test/` | mirrors `lib/`, same owner as the file under test |
