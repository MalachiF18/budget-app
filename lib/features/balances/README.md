# Balances (4.1–4.6)

- `split_math.dart`: deterministic integer-cent even splits.
- `balance_engine.dart`: pairwise balances and 7/30-day activity filtering.
- `example_ledger.dart`: explicit expenses reproducing the supplied mockup.
- `payment_sheet.dart`: receiver-only partial/full payment recording.

The Group screen renders this engine, and its repository calls the existing
receiver-only `record_payment` RPC. Unit, widget and HTTP contract tests live in
`test/features/balances/`.

See `docs/BALANCES_AND_DEMO.md` for filter semantics, the security contract,
running demo mode and a timed two-minute walkthrough.
