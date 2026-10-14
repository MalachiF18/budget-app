# Database

Supabase Postgres. Trello cards 1.5 (schema), 1.6 (security rules), 1.7 (join by
sync code), 1.8 (receipt storage).

Money is `bigint` cents everywhere. `$12.34` is `1234`.

## Applying the migrations

Files in `supabase/migrations/`, applied in name order:

| File | Contents |
|---|---|
| `20261014000001_core.sql` | tables, constraints, indexes, shares-sum trigger |
| `20261014000002_rls.sql` | grants, row-level security, Realtime publication |
| `20261014000003_functions.sql` | the group write functions (RPCs) |
| `20261014000004_storage.sql` | `receipts` bucket and its policies |

**Dashboard:** Supabase dashboard, SQL Editor, New query. Paste each file in
order and Run. Each file runs as one transaction: if it errors, nothing from that
file is applied.

**CLI:** `supabase link --project-ref <ref>` then `supabase db push`.

Apply each migration once. They are not written to be re-run.

**Then test:** paste `supabase/tests/rls_test.sql` into the SQL Editor and Run.
It always ends with an error on purpose. The error message is the report
(`RLS TEST REPORT: N passed, M failed`), and the error rolls everything back.

Also in the dashboard: Authentication, Sign In / Providers, enable **anonymous
sign-ins**.

## Tables

| Table | Holds |
|---|---|
| `profiles` | `display_name` (1 to 40 chars, no leading or trailing spaces) per user |
| `budgets` | one per user: `earnings_cents`, `savings_mode` (`fixed` or `percent`), `savings_value` (cents, or a whole percent 0 to 100) |
| `budget_items` | `kind` (`bill`, `subscription`, `one_time`), `name`, `amount_cents`, `month` (first day of the month; set for `one_time` only, null otherwise) |
| `transactions` | logged spending: `description`, `amount_cents` (> 0), `occurred_on` |
| `groups` | `name`, `sync_code` (12 chars), `created_by` |
| `group_members` | `group_id`, `user_id`, `joined_at` |
| `expenses` | `paid_by`, `created_by`, `description`, `amount_cents` (> 0), `occurred_on`, `receipt_path`, `updated_at` |
| `expense_shares` | `expense_id`, `user_id`, `share_cents` (>= 0). Shares always add up to the expense amount |
| `payments` | `from_user`, `to_user`, `amount_cents` (> 0), `occurred_on`, `recorded_by` (always `to_user`) |
| `join_attempts` | failed join attempts, used to slow down code guessing. Clients can't read it |

Every user in an expense, share or payment must be a member of that group. The
database enforces this, not only the app. A user who appears in a group ledger
can't be deleted, so ledger history can't disappear.

## Who can do what

Anonymous sign-in users have the `authenticated` role. Clients that aren't signed
in (`anon`) get nothing.

| Table | Read | Write |
|---|---|---|
| `profiles` | yourself, and people in a group with you | insert and update your own row only |
| `budgets`, `budget_items`, `transactions` | owner only | owner only, directly (insert, update, delete) |
| `groups`, `group_members` | members of that group | functions only |
| `expenses`, `expense_shares` | members of that group | functions only. Edit and delete are for the creator only |
| `payments` | members of that group | functions only. Only the receiver records or deletes |
| `join_attempts` | nobody | `join_group` only |

Clients have no insert, update or delete permission on any group table. Every
group write goes through one of the functions below.

## Functions (RPCs)

Call with `supabase.rpc('name', params: {...})` using the parameter names shown.
Each function finds the caller from their sign-in. None of them takes a caller
id, so nobody can act as somebody else. Errors come back as plain English the
app can show.

| Function | Returns | Who | Notes |
|---|---|---|---|
| `create_group(p_name text)` | one row: `group_id uuid, sync_code text` | any signed-in user with a profile | caller becomes the first member |
| `join_group(p_code text)` | `uuid` group id, or **`null` if no group has that code** | any signed-in user with a profile | ignores dashes, spaces and case. Joining a group you're already in returns its id |
| `add_expense(p_group_id uuid, p_description text, p_amount_cents bigint, p_shares jsonb, p_occurred_on date = today, p_paid_by uuid = caller, p_receipt_path text = null)` | expense `uuid` | members | caller is `created_by` |
| `update_expense(p_expense_id uuid, p_description text, p_amount_cents bigint, p_occurred_on date, p_shares jsonb, p_paid_by uuid = caller, p_receipt_path text = null)` | nothing | creator only | **replaces the whole expense.** A null `p_receipt_path` removes the receipt link, so send the current path to keep it |
| `delete_expense(p_expense_id uuid)` | the deleted `receipt_path` or null | creator only | the app then deletes that file from storage |
| `record_payment(p_group_id uuid, p_from_user uuid, p_amount_cents bigint, p_occurred_on date = today)` | payment `uuid` | the receiver | caller is `to_user` and `recorded_by`. Payments can't be edited |
| `delete_payment(p_payment_id uuid)` | nothing | the receiver who recorded it | to fix a mistake, delete it and record it again |

`p_shares` format: `[{"user_id": "<uuid>", "share_cents": 1000}, ...]`. Each
person appears once, each is a member, `share_cents` is a whole number >= 0, and
the shares add up exactly to `p_amount_cents`. The app does the split (leftover
cents go to the first people) and sends the result.

A profile must exist before `create_group` or `join_group`. Insert it into
`profiles` (`id` = your user id) when the user picks a name.

Readable helpers: `is_group_member(uuid)` and `shares_group_with(uuid)` return a
boolean, and each answers only about the caller.

## Sync codes and guessing

- 12 characters from `ABCDEFGHJKMNPQRSTUVWXYZ23456789`, with no `0 O 1 I L`.
  That's 31^12, about 8 x 10^17 codes. Generated on the server with
  `gen_random_bytes`, with no modulo bias. Stored uppercase without dashes. The
  app can show it as `ABCD-EFGH-JKMN`.
- **Guessing friction:** every unknown code is logged in `join_attempts`. After
  **10 wrong codes in 15 minutes**, `join_group` refuses that user, even for a
  correct code, until the window passes (error `Too many wrong codes...`).
  Unknown codes return `null` instead of raising an error. An error would roll
  back the logged attempt, and the counter would never grow.
- Limit: a guesser can make new anonymous users to reset the counter. Supabase
  limits anonymous sign-ins per IP (30 per hour by default). With 8 x 10^17
  codes, guessing isn't practical either way.

## Realtime

Supabase Realtime **doesn't apply RLS to DELETE events.** Every subscriber to a
table gets every delete on it, with the row's primary key.

So only **`expenses`** and **`payments`** are published. Their primary key is a
random uuid, so a delete reveals a meaningless id and nothing else. INSERT and
UPDATE events are filtered by RLS, so members only see their own groups.

Not published, on purpose:

- `expense_shares`: its key `(expense_id, user_id)` would reveal user ids on delete
- `group_members`: its key `(group_id, user_id)` would reveal who is in which group
- `groups`, because it holds the sync code
- `profiles`, the personal tables and `join_attempts`

**App pattern:** subscribe to `expenses` and `payments` filtered by
`group_id=eq.<id>`. On any event, refetch the group's ledger (expenses, shares,
payments). Delete events can't be filtered by `group_id`, so for a DELETE, check
whether the id is one you're showing. `update_expense` always updates the
`expenses` row, so share changes also send an event. Members joining don't send
a live event. Refetch members when the screen opens.

## Receipts (storage)

- Private bucket `receipts`, max 5 MiB, `image/jpeg`, `image/png`, `image/webp`
  only. The Storage API enforces these limits.
- Path: `{group_id}/{uuid}.{jpg|jpeg|png|webp}`, with lowercase uuids. Any other
  path is refused.
- Read: members of that group (use signed URLs or `download`, because the bucket
  isn't public).
- Upload: members, into their own group's folder only.
- Replace or delete: only the uploader.
- Order: upload first with a new uuid, then pass the path to `add_expense`. After
  `delete_expense`, delete the returned path from storage.
