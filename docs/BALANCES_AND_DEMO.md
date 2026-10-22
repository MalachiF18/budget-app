# Balances and payments (4.1–4.6)

`splitAmount(cents, count)` splits integer cents and gives one extra cent to each
of the first remainder participants. The group form's `splitCents` adapter sorts
unique user IDs first, so the same participants always receive the same shares.
$10 / 3 gives $3.34 + $3.33 + $3.33. No floating-point money is used.

`BalanceEngine` starts with each expense participant's debt to its payer, ignores
the payer's own share, subtracts recorded payments, and nets opposite obligations
within each pair. It never transfers debts between unrelated people. Credit from
an imported overpayment remains visible in the opposite direction.

The fixture in `example_ledger.dart` totals $132: you paid $30 for Davante;
Malachi paid $48 ($12 charged to you and $36 to himself); Jordan paid $54 ($18 to
you and $36 to himself). This produces the supplied screenshot's $12 owed to
Malachi, $18 owed to Jordan and $30 owed by Davante. The screenshot did not give
its underlying expenses; these explicit fixture expenses reproduce its amounts.

Group activity defaults to ALL. W and M mean the last 7 and 30 local calendar
days, including today, through the end of today. ALL has no date restriction.
The fixture expenses are today, 10 days ago and 40 days ago, so W/M/ALL totals
are $30/$78/$132. Member spending, expense rows and payment rows all use the same
filter. Outstanding debts always use all activity, and the screen says so. A
payment this week against an older expense must not create a false reverse debt.

The receiver alone sees Record received payment on a member's card when that
member owes them. Amount defaults to the full outstanding balance, date defaults
to today, and both can be changed. Partial payments work. Zero, excess precision,
and amounts above the displayed debt are rejected. Saving disables repeat taps;
a failure leaves the sheet open without changing balances. Success refetches the
ledger, and payments share the dated ledger with expenses. This records an
external transfer; the app does not move money.

Production calls the existing `record_payment` RPC. No receiver or recorded_by
argument is accepted: both come from `auth.uid()`. Existing grants prohibit
direct writes to payments. Existing SQL regression checks 12, 17, 17b and 17c
cover receiver recording and payer denial. No new migration is required for 4.x;
the original migrations through `20261014000004_storage.sql` must be deployed.
The Personal feature still requires its October 19 save migration.

Davante's `davante/group-expenses` branch is integrated as the group foundation,
preserving its create/join, expenses, receipt and realtime behavior. Member ledger
filtering now includes charged expenses and payments as well as paid expenses.

# Run the demo

From a checkout with Flutter 3.47.2 on PATH:

```sh
flutter pub get
flutter run -d web-server --web-port=8765 --dart-define=DEMO_MODE=true
```

Open http://localhost:8765 in your browser. Keep the command running. Demo mode
bypasses Supabase entirely and shows example-data labels. Reload the browser to
reset the sample. Demo changes last only until reload; do not use it as evidence
of cloud persistence, multi-user realtime or receipt upload to Supabase.

For a phone/emulator, use `flutter run --dart-define=DEMO_MODE=true` and select
your connected device. For the live app omit DEMO_MODE and apply migrations.

# Two-minute walkthrough

| Time | Action | What to say / expected result |
|---|---|---|
| 0:00–0:15 | Open Personal; tap W, Y, then M. | “The budget is stored as monthly cents and projected weekly or yearly.” |
| 0:15–0:35 | Open Savings target; change 15% to 20%; save. | Savings becomes $267.00 and Spending money updates. Mention the fixed-amount switch. |
| 0:35–0:50 | Scroll to Spending money; Add transaction: Coffee, $5.00, today's date; save. | Spending money drops by $5. The dated transaction appears underneath. |
| 0:50–1:05 | Switch to Group. | “ALL shows $132 spent. I owe Malachi $12 and Jordan $18; Davante owes me $30.” |
| 1:05–1:20 | Tap W, M, ALL. | Totals change $30 → $78 → $132. Explain that current debts stay all-time. |
| 1:20–1:40 | On Davante's card, Record received payment; enter $15; save. | “Only the receiver records it.” Davante's debt drops from $30 to $15. Point out no payment button on Malachi/Jordan's cards. |
| 1:40–1:50 | Tap Davante's card; scroll to ledger. | Show the $15 received payment with today's date alongside Lunch for Davante. |
| 1:50–2:00 | Explain the split rule; optionally show pre-opened tests. | “$10 split three ways is $3.34, $3.33, $3.33. Every cent is assigned.” |

Two minutes is enough to demonstrate representative flows, not to exercise every
add/edit/remove, receipt and failure case. Have `flutter test` results open before
recording. If you also want to demonstrate the integrated group expense form,
replace 0:15–0:35 with: Group → Add expense → $10 → select Malachi and Davante,
leave Share with me on, and save; each receives $3.34/$3.33/$3.33 in stable user-id
order. This changes the later balances, so use a fresh reload for the script above.

For a live persistence demo, use the real app and two signed-in accounts; close
and reopen after an edit, and record a payment on the receiver's account. That
requires database access and preparation and is separate from this offline demo.
