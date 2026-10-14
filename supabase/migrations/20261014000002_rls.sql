-- Grants and row-level security. Trello card 1.6.
--
-- Roles: anonymous sign-in users get the `authenticated` role (with an
-- is_anonymous claim), not `anon`. `anon` is a client that has not signed in
-- at all; it gets nothing here.
--
-- Supabase's default privileges grant ALL on new public tables and functions
-- to anon and authenticated, so every table starts with "revoke all" and
-- gets back only what it needs.

-- ---------------------------------------------------------------------------
-- Membership helpers.
--
-- SECURITY DEFINER so a policy on group_members can ask "is the caller a
-- member" without re-entering group_members' own policy (infinite recursion).
-- They only answer about the caller, so exposing them as RPCs leaks nothing.
-- ---------------------------------------------------------------------------

create function public.is_group_member(p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and exists (
    select 1 from public.group_members
    where group_id = p_group_id and user_id = auth.uid()
  );
$$;

-- True when the caller and p_user are in at least one group together.
create function public.shares_group_with(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and exists (
    select 1
    from public.group_members me
    join public.group_members them on them.group_id = me.group_id
    where me.user_id = auth.uid() and them.user_id = p_user
  );
$$;

revoke all on function public.is_group_member(uuid), public.shares_group_with(uuid)
  from public, anon, authenticated;
-- Policies run with the querying role's privileges, so it needs EXECUTE.
grant execute on function public.is_group_member(uuid), public.shares_group_with(uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Enable RLS everywhere. A table with RLS on and no policy is closed.
-- ---------------------------------------------------------------------------

alter table public.profiles       enable row level security;
alter table public.budgets        enable row level security;
alter table public.budget_items   enable row level security;
alter table public.transactions   enable row level security;
alter table public.groups         enable row level security;
alter table public.group_members  enable row level security;
alter table public.join_attempts  enable row level security;
alter table public.expenses       enable row level security;
alter table public.expense_shares enable row level security;
alter table public.payments       enable row level security;

revoke all on
  public.profiles, public.budgets, public.budget_items, public.transactions,
  public.groups, public.group_members, public.join_attempts,
  public.expenses, public.expense_shares, public.payments
from public, anon, authenticated;

grant all on
  public.profiles, public.budgets, public.budget_items, public.transactions,
  public.groups, public.group_members, public.join_attempts,
  public.expenses, public.expense_shares, public.payments
to service_role;

-- join_attempts: no grants, no policies. Only join_group() touches it.

-- ---------------------------------------------------------------------------
-- profiles: read your own and those of people you share a group with
-- (display names on member cards); write only your own.
-- ---------------------------------------------------------------------------

grant select, insert, update on public.profiles to authenticated;

create policy "profiles: read self and group-mates" on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or public.shares_group_with(id));

create policy "profiles: create own" on public.profiles
  for insert to authenticated
  with check (id = (select auth.uid()));

create policy "profiles: update own" on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- No delete policy: a profile goes away only with its auth user.

-- ---------------------------------------------------------------------------
-- Personal tables: owner reads and writes directly.
-- ---------------------------------------------------------------------------

grant select, insert, update, delete on
  public.budgets, public.budget_items, public.transactions
to authenticated;

create policy "budgets: owner all" on public.budgets
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- Ownership follows the parent budget. The subquery is itself filtered by
-- the budgets policy, so it only ever finds the caller's own budget.
create policy "budget_items: owner all" on public.budget_items
  for all to authenticated
  using (exists (select 1 from public.budgets b
                 where b.id = budget_id and b.user_id = (select auth.uid())))
  with check (exists (select 1 from public.budgets b
                      where b.id = budget_id and b.user_id = (select auth.uid())));

create policy "transactions: owner all" on public.transactions
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- Group tables: members read; nobody writes directly (no insert/update/delete
-- grant). Writes go through the SECURITY DEFINER functions in 0003.
-- ---------------------------------------------------------------------------

grant select on
  public.groups, public.group_members, public.expenses,
  public.expense_shares, public.payments
to authenticated;

create policy "groups: members read" on public.groups
  for select to authenticated
  using (public.is_group_member(id));

create policy "group_members: members read" on public.group_members
  for select to authenticated
  using (public.is_group_member(group_id));

create policy "expenses: members read" on public.expenses
  for select to authenticated
  using (public.is_group_member(group_id));

create policy "expense_shares: members read" on public.expense_shares
  for select to authenticated
  using (exists (select 1 from public.expenses e
                 where e.id = expense_id and public.is_group_member(e.group_id)));

create policy "payments: members read" on public.payments
  for select to authenticated
  using (public.is_group_member(group_id));

-- ---------------------------------------------------------------------------
-- Realtime.
--
-- Supabase Realtime does not apply RLS to DELETE events: every subscriber to
-- a table receives every delete on it. With RLS on and the default replica
-- identity, a delete payload carries only the primary key.
--
-- So publish only tables whose primary key is a bare random uuid:
--   expenses (id), payments (id).
-- INSERT/UPDATE events on them are RLS-filtered (members only).
-- A delete leaks one meaningless uuid to other subscribers, nothing else.
--
-- NOT published, on purpose:
--   expense_shares  PK (expense_id, user_id) would leak user ids on delete
--   group_members   PK (group_id, user_id) would leak who is in which group
--   groups          carries sync_code
--   profiles, personal tables, join_attempts
-- update_expense always touches the expenses row, so a share change still
-- produces an expenses UPDATE event; the client refetches on any event.
--
-- If a table is ever added here, check its primary key first: that is
-- exactly what every subscriber will see when one of its rows is deleted.
-- ---------------------------------------------------------------------------

alter publication supabase_realtime add table public.expenses, public.payments;
