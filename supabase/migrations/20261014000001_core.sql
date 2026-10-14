-- Core schema: tables, constraints, indexes. Trello card 1.5.
--
-- Money is always bigint cents ($12.34 = 1234), never numeric or float, so the
-- app and the database add up the same way.
--
-- No begin/commit here: `supabase db push` wraps each migration in its own
-- transaction, and the dashboard SQL editor runs a pasted script as one
-- implicit transaction.

-- gen_random_bytes() for sync codes. Supabase installs pgcrypto in the
-- `extensions` schema; this is a no-op when it is already there.
create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- Users
-- ---------------------------------------------------------------------------

-- One row per signed-in user (anonymous sign-in still creates an auth.users
-- row). The app creates it once, when the user picks a display name.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null
    check (char_length(display_name) between 1 and 40
           and display_name = btrim(display_name)),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Personal budget (owner-only; the owner writes these directly through RLS)
-- ---------------------------------------------------------------------------

create table public.budgets (
  id uuid primary key default gen_random_uuid(),
  -- One budget per user, enforced by the unique constraint.
  user_id uuid not null unique default auth.uid()
    references auth.users (id) on delete cascade,
  earnings_cents bigint not null default 0 check (earnings_cents >= 0),
  savings_mode text not null default 'fixed'
    check (savings_mode in ('fixed', 'percent')),
  -- Cents when savings_mode = 'fixed'; a whole percent 0..100 when 'percent'.
  savings_value bigint not null default 0
    check (savings_value >= 0
           and (savings_mode <> 'percent' or savings_value <= 100)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.budget_items (
  id uuid primary key default gen_random_uuid(),
  budget_id uuid not null references public.budgets (id) on delete cascade,
  kind text not null check (kind in ('bill', 'subscription', 'one_time')),
  name text not null check (char_length(name) between 1 and 60 and name = btrim(name)),
  amount_cents bigint not null check (amount_cents >= 0),
  -- Bills and subscriptions repeat every month, so they carry no month.
  -- A one-time need belongs to one month, stored as that month's first day.
  month date check (month is null or month = date_trunc('month', month)::date),
  created_at timestamptz not null default now(),
  check ((kind = 'one_time') = (month is not null))
);
create index budget_items_budget_id_idx on public.budget_items (budget_id);

-- Logged spending ("logged spending" in the Spending money formula).
create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  description text not null
    check (char_length(description) between 1 and 100 and description = btrim(description)),
  amount_cents bigint not null check (amount_cents > 0),
  occurred_on date not null default current_date,
  created_at timestamptz not null default now()
);
create index transactions_user_occurred_idx on public.transactions (user_id, occurred_on);

-- ---------------------------------------------------------------------------
-- Groups (read-only to clients; every write goes through 0003 functions)
-- ---------------------------------------------------------------------------

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 60 and name = btrim(name)),
  -- 12 characters, uppercase, no dashes, no look-alikes (0 O 1 I L).
  -- Generated server-side by public.generate_sync_code().
  sync_code text not null unique check (sync_code ~ '^[A-HJKMNP-Z2-9]{12}$'),
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now()
);

create table public.group_members (
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
-- "Which groups am I in" (the PK only serves lookups by group first).
create index group_members_user_id_idx on public.group_members (user_id);

-- Failed join attempts, for brute-force friction in public.join_group().
-- Never readable by clients.
create table public.join_attempts (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  attempted_at timestamptz not null default now()
);
create index join_attempts_user_time_idx on public.join_attempts (user_id, attempted_at);

-- ---------------------------------------------------------------------------
-- Expenses and payments
--
-- User references point at profiles with the default NO ACTION: ledger
-- history must not silently vanish, so a user who appears in a ledger cannot
-- be deleted until those rows are dealt with.
--
-- The composite foreign keys onto group_members make "paid_by / from_user /
-- to_user must be a member of this group" a database fact, not only an
-- RPC check.
-- ---------------------------------------------------------------------------

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  paid_by uuid not null references public.profiles (id),
  created_by uuid not null references public.profiles (id),
  description text not null
    check (char_length(description) between 1 and 100 and description = btrim(description)),
  amount_cents bigint not null check (amount_cents > 0),
  occurred_on date not null default current_date,
  -- Object path inside the private `receipts` bucket: {group_id}/{uuid}.{ext}
  receipt_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (group_id, paid_by) references public.group_members (group_id, user_id),
  foreign key (group_id, created_by) references public.group_members (group_id, user_id)
);
create index expenses_group_occurred_idx on public.expenses (group_id, occurred_on);

create table public.expense_shares (
  expense_id uuid not null references public.expenses (id) on delete cascade,
  user_id uuid not null references public.profiles (id),
  share_cents bigint not null check (share_cents >= 0),
  primary key (expense_id, user_id)
);
create index expense_shares_user_id_idx on public.expense_shares (user_id);

-- Money received. Recorded only by the receiver: recorded_by = to_user.
create table public.payments (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  from_user uuid not null references public.profiles (id),
  to_user uuid not null references public.profiles (id),
  amount_cents bigint not null check (amount_cents > 0),
  occurred_on date not null default current_date,
  recorded_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  check (from_user <> to_user),
  check (recorded_by = to_user),
  foreign key (group_id, from_user) references public.group_members (group_id, user_id),
  foreign key (group_id, to_user) references public.group_members (group_id, user_id)
);
create index payments_group_occurred_idx on public.payments (group_id, occurred_on);
create index payments_from_user_idx on public.payments (from_user);
create index payments_to_user_idx on public.payments (to_user);

-- ---------------------------------------------------------------------------
-- Shares must add up to the expense amount, and every share user must be a
-- member of the expense's group.
--
-- The write RPCs check this first and give a friendly error. This trigger is
-- the backstop for any other writer (dashboard edits, a future function).
-- It is DEFERRED to commit time because an expense and its shares are
-- written in separate statements: checking after the first statement would
-- always see zero shares.
--
-- SECURITY DEFINER because a deferred trigger runs at commit, after the
-- calling RPC has returned, i.e. as the client's own role; it must see every
-- share row regardless of RLS.
-- ---------------------------------------------------------------------------

create function public.check_expense_shares()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ids uuid[];
  v_id uuid;
  v_amount bigint;
  v_group uuid;
  v_sum bigint;
begin
  if tg_table_name = 'expenses' then
    v_ids := array[new.id];
  elsif tg_op = 'DELETE' then
    v_ids := array[old.expense_id];
  elsif tg_op = 'UPDATE' then
    v_ids := array[old.expense_id, new.expense_id];
  else
    v_ids := array[new.expense_id];
  end if;

  foreach v_id in array v_ids loop
    select e.amount_cents, e.group_id into v_amount, v_group
      from public.expenses e where e.id = v_id;
    -- Expense deleted in the same transaction (its shares cascade): nothing to check.
    continue when not found;

    select coalesce(sum(s.share_cents), 0) into v_sum
      from public.expense_shares s where s.expense_id = v_id;
    if v_sum <> v_amount then
      raise exception 'Shares must add up to the expense amount (% <> %)', v_sum, v_amount
        using errcode = 'check_violation';
    end if;

    if exists (
      select 1 from public.expense_shares s
      where s.expense_id = v_id
        and not exists (select 1 from public.group_members m
                         where m.group_id = v_group and m.user_id = s.user_id)
    ) then
      raise exception 'Every person charged must be a member of the group'
        using errcode = 'check_violation';
    end if;
  end loop;
  return null;
end;
$$;

create constraint trigger expense_shares_sum_check
  after insert or update or delete on public.expense_shares
  deferrable initially deferred
  for each row execute function public.check_expense_shares();

create constraint trigger expenses_shares_sum_check
  after insert or update on public.expenses
  deferrable initially deferred
  for each row execute function public.check_expense_shares();

-- Trigger functions are not an API. Supabase's default privileges grant
-- EXECUTE on new public functions to anon and authenticated, so revoke both.
revoke all on function public.check_expense_shares() from public, anon, authenticated;
