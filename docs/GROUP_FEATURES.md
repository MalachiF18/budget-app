# Group expenses

The Group tab uses the existing violet Group theme. The mockup is access
restricted; an exact visual comparison is still pending.

- Create and Join call the existing `create_group` and `join_group` RPCs.
  The selected group displays its selectable sync code and Copy button.
- Group selection reloads from Supabase. ALL is selected whenever a group opens.
  W means the current Monday–Sunday week; M means the current calendar month.
- Member cards display paid totals and net owed/owing balances, including
  recorded payments for the selected period. Balances are group-wide net
  positions, not pairwise settlement instructions.
- A member card filters the ledger by `paid_by`. Show all clears that filter.
- Charge checkboxes represent other members. They start unchecked. The current
  user's separate Share with me switch starts on. Select/Deselect all affects
  the checkboxes, not that switch. One selected person with the switch off is
  charged the full amount. Empty splits are rejected. Cents split exactly,
  with remainder cents assigned in stable user-id order.
- Camera/gallery receipts upload to the private `receipts` bucket, using a fresh
  UUID path and verified JPEG/PNG/WebP signature. Maximum upload is 5 MiB.
  Receipt icons download the authenticated image and open a zoomable view.
- Edits preserve receipt paths and payer identity. Replacement uploads are
  removed on save failure; obsolete files are cleaned up after success.
- Edit/Delete depend on `created_by`, not `paid_by`. The repository checks this
  too; the existing RPC creator checks and table grants enforce it server-side.
- Realtime expense/payment insert/update events refetch the ledger. Delete
  events cannot be group-filtered, so they also trigger a refetch under RLS.
  Reconnect, app resume, tab reopening, and pull-to-refresh reload data.
- Failed receipt cleanup does not turn a successful expense mutation into a
  reported failure; a cleanup failure can leave an unreferenced storage object.

## Validation

The existing CI runs formatting, analysis, the complete widget/unit suite and
an Android release build. `test/features/group/group_test.dart` covers the form
 defaults, select/deselect, direct charges, empty-split rejection, create/copy,
join/navigation, ALL selection, payer filtering, ownership controls and live
refetching. Existing `supabase/tests/rls_test.sql` covers unauthorized edits and
deletes. No database schema change is needed.

Still verify on the deployed Supabase project with two signed-in devices:

1. A creates a group and copies its code. B joins with that code.
2. A reopens Group to load the newly joined member.
3. A adds an expense charging B only with Share with me off. B sees the full
   charge without refreshing. Edit and delete propagate too.
4. Attach one camera receipt and one gallery receipt. B can open both but has
   no Edit/Delete controls on A's expenses.
5. Repeat with an uneven-cent shared expense; shares must total the amount.
6. Check the accessible mockup against the Group screen before visual signoff.

Local Flutter validation was blocked by environment approval review during
Flutter startup. Tests and two-device behavior are not yet certified as passing.
