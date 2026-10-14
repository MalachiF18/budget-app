-- Group write API. Trello cards 1.5 / 1.7.
--
-- Clients have no insert/update/delete grant on any group table (0002).
-- Every group write is one of the SECURITY DEFINER functions below. Each one:
--   * sets search_path = '' and schema-qualifies everything, so a caller
--     cannot redirect a name to an object of their own;
--   * reads the caller only from auth.uid(), never from an argument;
--   * re-checks membership / ownership itself, because SECURITY DEFINER
--     bypasses RLS.
--
-- Errors are raised with plain-English messages the app can show as-is.

-- ---------------------------------------------------------------------------
-- Internal helpers (EXECUTE revoked from clients at the bottom)
-- ---------------------------------------------------------------------------

-- 12 characters from a 31-character alphabet with no look-alikes
-- (no 0 O 1 I L): 31^12 is about 7.9e17 codes (~59 bits).
--
-- Uses pgcrypto's gen_random_bytes (a CSPRNG), not random(), which is
-- predictable. Rejection sampling: only bytes below 248 (= 31 * 8) are used,
-- so `byte % 31` hits every character equally often (no modulo bias).
create function public.generate_sync_code()
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_code text := '';
  v_bytes bytea;
  v_byte integer;
  i integer;
begin
  while char_length(v_code) < 12 loop
    v_bytes := extensions.gen_random_bytes(16);
    for i in 0 .. 15 loop
      v_byte := get_byte(v_bytes, i);
      if v_byte < 248 and char_length(v_code) < 12 then
        v_code := v_code || substr(v_alphabet, (v_byte % 31) + 1, 1);
      end if;
    end loop;
  end loop;
  return v_code;
end;
$$;

-- Group id encoded in a receipt object path, or null if the path is not
-- exactly {group_uuid}/{uuid}.{jpg|jpeg|png|webp} (lowercase uuids, as
-- Postgres and the Dart uuid package print them). Used by the expense RPCs
-- and by the storage policies in 0004, so both agree on one format.
create function public.receipt_group_id(p_path text)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select case
    when p_path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|jpeg|png|webp)$'
    then split_part(p_path, '/', 1)::uuid
  end;
$$;

-- Validates the shares array for an expense in p_group_id totalling
-- p_amount_cents. Raises on any problem; returns nothing.
-- Expected shape: [{"user_id": "<uuid>", "share_cents": 1234}, ...]
create function public.validate_expense_shares(
  p_group_id uuid,
  p_amount_cents bigint,
  p_shares jsonb
)
returns void
language plpgsql
stable
set search_path = ''
as $$
declare
  v_count integer;
  v_distinct integer;
  v_sum numeric;
begin
  if p_shares is null or jsonb_typeof(p_shares) <> 'array'
     or jsonb_array_length(p_shares) = 0 then
    raise exception 'Pick at least one person to charge';
  end if;

  -- Shape check before any cast, so a bad element gives this message rather
  -- than a cast error. share_cents must be a non-negative whole number.
  if exists (
    select 1 from jsonb_array_elements(p_shares) e
    where jsonb_typeof(e) <> 'object'
       or jsonb_typeof(e -> 'user_id') is distinct from 'string'
       or (e ->> 'user_id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or jsonb_typeof(e -> 'share_cents') is distinct from 'number'
       or (e ->> 'share_cents') !~ '^[0-9]{1,15}$'
  ) then
    raise exception 'Each share needs a user_id and a whole, non-negative share_cents';
  end if;

  -- Sum as numeric so a huge input cannot overflow before the comparison.
  select count(*), count(distinct (e ->> 'user_id')::uuid),
         coalesce(sum((e ->> 'share_cents')::numeric), 0)
    into v_count, v_distinct, v_sum
    from jsonb_array_elements(p_shares) e;

  if v_distinct <> v_count then
    raise exception 'Each person can appear only once in the shares';
  end if;

  if v_sum <> p_amount_cents then
    raise exception 'Shares must add up to the expense amount (% <> %)', v_sum, p_amount_cents;
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_shares) e
    where not exists (select 1 from public.group_members m
                      where m.group_id = p_group_id
                        and m.user_id = (e ->> 'user_id')::uuid)
  ) then
    raise exception 'Every person charged must be a member of the group';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- create_group(name) -> (group_id, sync_code)
-- ---------------------------------------------------------------------------

create function public.create_group(p_name text)
returns table (group_id uuid, sync_code text)
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
  v_name text := btrim(coalesce(p_name, ''));
  v_code text;
  v_group uuid;
  v_try integer;
begin
  if v_user is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_user) then
    raise exception 'Set your display name first';
  end if;
  if char_length(v_name) not between 1 and 60 then
    raise exception 'Group name must be 1 to 60 characters';
  end if;

  -- A collision at ~59 bits is practically impossible, but must never put
  -- two groups behind one code; retry with a fresh code.
  for v_try in 1 .. 5 loop
    v_code := public.generate_sync_code();
    begin
      insert into public.groups (name, sync_code, created_by)
        values (v_name, v_code, v_user)
        returning id into v_group;
      insert into public.group_members (group_id, user_id)
        values (v_group, v_user);
      group_id := v_group;
      sync_code := v_code;
      return next;
      return;
    exception when unique_violation then
      null;
    end;
  end loop;
  raise exception 'Could not create the group. Please try again';
end;
$$;

-- ---------------------------------------------------------------------------
-- join_group(code) -> group id, or NULL when no group has that code.
--
-- Input is normalised: dashes and whitespace removed, uppercased, so
-- "abcd-efgh-jkmn" works.
--
-- Brute-force friction: each failed attempt is stored in join_attempts. A
-- caller with 10 failures in the last 15 minutes is refused (exception)
-- before the code is even looked up. Unknown codes RETURN NULL instead of
-- raising, because raising would roll back the attempt row and the counter
-- would never grow. Joining a group you are already in returns its id and
-- does not count as a failure.
-- ---------------------------------------------------------------------------

create function public.join_group(p_code text)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[\s-]', '', 'g'));
  v_group uuid;
begin
  if v_user is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_user) then
    raise exception 'Set your display name first';
  end if;

  -- Keep the table small: this user's attempts older than the window are useless.
  delete from public.join_attempts
    where user_id = v_user and attempted_at < now() - interval '15 minutes';

  if (select count(*) from public.join_attempts where user_id = v_user) >= 10 then
    raise exception 'Too many wrong codes. Wait 15 minutes and try again'
      using errcode = '54000';
  end if;

  select g.id into v_group from public.groups g where g.sync_code = v_code;
  if v_group is null then
    insert into public.join_attempts (user_id) values (v_user);
    return null;
  end if;

  insert into public.group_members (group_id, user_id)
    values (v_group, v_user)
    on conflict (group_id, user_id) do nothing;
  return v_group;
end;
$$;

-- ---------------------------------------------------------------------------
-- add_expense(...) -> expense id
--
-- p_paid_by defaults to the caller. p_occurred_on defaults to today.
-- p_shares: [{"user_id": "<uuid>", "share_cents": 1234}, ...], must sum to
-- p_amount_cents, every user a group member. The app does the even split
-- (leftover cents to the first people) and sends the result.
-- p_receipt_path: optional, '{group_id}/{uuid}.{ext}' in the receipts bucket.
-- ---------------------------------------------------------------------------

create function public.add_expense(
  p_group_id uuid,
  p_description text,
  p_amount_cents bigint,
  p_shares jsonb,
  p_occurred_on date default null,
  p_paid_by uuid default null,
  p_receipt_path text default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_paid_by uuid := coalesce(p_paid_by, auth.uid());
  v_description text := btrim(coalesce(p_description, ''));
  v_expense uuid;
begin
  if v_user is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;
  if not public.is_group_member(p_group_id) then
    raise exception 'You are not a member of this group' using errcode = '42501';
  end if;
  if char_length(v_description) not between 1 and 100 then
    raise exception 'Description must be 1 to 100 characters';
  end if;
  if p_amount_cents is null or p_amount_cents <= 0 then
    raise exception 'Amount must be more than zero';
  end if;
  if not exists (select 1 from public.group_members m
                 where m.group_id = p_group_id and m.user_id = v_paid_by) then
    raise exception 'The person who paid must be a member of the group';
  end if;
  if p_receipt_path is not null
     and public.receipt_group_id(p_receipt_path) is distinct from p_group_id then
    raise exception 'Receipt path must be {group_id}/{uuid}.jpg, .jpeg, .png or .webp';
  end if;
  perform public.validate_expense_shares(p_group_id, p_amount_cents, p_shares);

  insert into public.expenses
    (group_id, paid_by, created_by, description, amount_cents, occurred_on, receipt_path)
  values
    (p_group_id, v_paid_by, v_user, v_description, p_amount_cents,
     coalesce(p_occurred_on, current_date), p_receipt_path)
  returning id into v_expense;

  insert into public.expense_shares (expense_id, user_id, share_cents)
    select v_expense, (e ->> 'user_id')::uuid, (e ->> 'share_cents')::bigint
    from jsonb_array_elements(p_shares) e;

  return v_expense;
end;
$$;

-- ---------------------------------------------------------------------------
-- update_expense(...) -> void. Creator only.
--
-- Full replacement: the app sends the whole edited expense. In particular
-- p_receipt_path = null REMOVES the receipt link, so send the current path
-- to keep it. p_paid_by null means the caller. Shares are replaced wholesale.
-- ---------------------------------------------------------------------------

create function public.update_expense(
  p_expense_id uuid,
  p_description text,
  p_amount_cents bigint,
  p_occurred_on date,
  p_shares jsonb,
  p_paid_by uuid default null,
  p_receipt_path text default null
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_paid_by uuid := coalesce(p_paid_by, auth.uid());
  v_description text := btrim(coalesce(p_description, ''));
  v_expense public.expenses%rowtype;
begin
  if v_user is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;

  select * into v_expense from public.expenses e where e.id = p_expense_id for update;
  -- Same message whether the expense is missing or someone else's, so
  -- outsiders learn nothing about which ids exist.
  if not found or v_expense.created_by <> v_user then
    raise exception 'Only the person who added this expense can change it'
      using errcode = '42501';
  end if;
  -- No leave-group function exists yet; check membership anyway so this
  -- stays correct if one is added.
  if not public.is_group_member(v_expense.group_id) then
    raise exception 'You are not a member of this group' using errcode = '42501';
  end if;
  if char_length(v_description) not between 1 and 100 then
    raise exception 'Description must be 1 to 100 characters';
  end if;
  if p_amount_cents is null or p_amount_cents <= 0 then
    raise exception 'Amount must be more than zero';
  end if;
  if p_occurred_on is null then
    raise exception 'Date is required';
  end if;
  if not exists (select 1 from public.group_members m
                 where m.group_id = v_expense.group_id and m.user_id = v_paid_by) then
    raise exception 'The person who paid must be a member of the group';
  end if;
  if p_receipt_path is not null
     and public.receipt_group_id(p_receipt_path) is distinct from v_expense.group_id then
    raise exception 'Receipt path must be {group_id}/{uuid}.jpg, .jpeg, .png or .webp';
  end if;
  perform public.validate_expense_shares(v_expense.group_id, p_amount_cents, p_shares);

  -- Always touches the row (updated_at), so Realtime emits an expenses
  -- UPDATE even when only the shares changed.
  update public.expenses
     set description = v_description,
         amount_cents = p_amount_cents,
         occurred_on = p_occurred_on,
         paid_by = v_paid_by,
         receipt_path = p_receipt_path,
         updated_at = now()
   where id = p_expense_id;

  delete from public.expense_shares where expense_id = p_expense_id;
  insert into public.expense_shares (expense_id, user_id, share_cents)
    select p_expense_id, (e ->> 'user_id')::uuid, (e ->> 'share_cents')::bigint
    from jsonb_array_elements(p_shares) e;
end;
$$;

-- ---------------------------------------------------------------------------
-- delete_expense(id) -> the deleted expense's receipt_path (or null).
-- Creator only. Shares cascade. The receipt object is NOT deleted here (SQL
-- cannot remove the file from storage); the app deletes it with the
-- returned path, through the Storage API, as its uploader.
-- ---------------------------------------------------------------------------

create function public.delete_expense(p_expense_id uuid)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_expense public.expenses%rowtype;
begin
  if v_user is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;
  select * into v_expense from public.expenses e where e.id = p_expense_id for update;
  if not found or v_expense.created_by <> v_user then
    raise exception 'Only the person who added this expense can delete it'
      using errcode = '42501';
  end if;
  delete from public.expenses where id = p_expense_id;
  return v_expense.receipt_path;
end;
$$;

-- ---------------------------------------------------------------------------
-- record_payment(group, from_user, amount, date) -> payment id
--
-- The caller is ALWAYS the receiver: to_user = recorded_by = auth.uid().
-- There is no argument for the receiver, so a payer cannot mark their own
-- debt paid. Payments are not editable; a mistake is fixed by the receiver
-- deleting it (delete_payment) and recording it again.
-- ---------------------------------------------------------------------------

create function public.record_payment(
  p_group_id uuid,
  p_from_user uuid,
  p_amount_cents bigint,
  p_occurred_on date default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_payment uuid;
begin
  if v_user is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;
  if not public.is_group_member(p_group_id) then
    raise exception 'You are not a member of this group' using errcode = '42501';
  end if;
  if p_from_user is null or p_from_user = v_user then
    raise exception 'Only the person who received the money can record a payment, from someone else';
  end if;
  if not exists (select 1 from public.group_members m
                 where m.group_id = p_group_id and m.user_id = p_from_user) then
    raise exception 'The person who paid must be a member of the group';
  end if;
  if p_amount_cents is null or p_amount_cents <= 0 then
    raise exception 'Amount must be more than zero';
  end if;

  insert into public.payments
    (group_id, from_user, to_user, amount_cents, occurred_on, recorded_by)
  values
    (p_group_id, p_from_user, v_user, p_amount_cents,
     coalesce(p_occurred_on, current_date), v_user)
  returning id into v_payment;
  return v_payment;
end;
$$;

-- delete_payment(id) -> void. Only the receiver who recorded it.
create function public.delete_payment(p_payment_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;
  delete from public.payments
   where id = p_payment_id and recorded_by = v_user and to_user = v_user;
  if not found then
    raise exception 'Only the person who received this payment can delete it'
      using errcode = '42501';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Privileges. Postgres grants EXECUTE to PUBLIC by default and Supabase's
-- default privileges add anon and authenticated, so revoke all three and
-- grant back only the API.
-- ---------------------------------------------------------------------------

revoke all on function
  public.generate_sync_code(),
  public.validate_expense_shares(uuid, bigint, jsonb),
  public.create_group(text),
  public.join_group(text),
  public.add_expense(uuid, text, bigint, jsonb, date, uuid, text),
  public.update_expense(uuid, text, bigint, date, jsonb, uuid, text),
  public.delete_expense(uuid),
  public.record_payment(uuid, uuid, bigint, date),
  public.delete_payment(uuid),
  public.receipt_group_id(text)
from public, anon, authenticated;

grant execute on function
  public.create_group(text),
  public.join_group(text),
  public.add_expense(uuid, text, bigint, jsonb, date, uuid, text),
  public.update_expense(uuid, text, bigint, date, jsonb, uuid, text),
  public.delete_expense(uuid),
  public.record_payment(uuid, uuid, bigint, date),
  public.delete_payment(uuid),
  -- Needed by the storage policies in 0004, which run as the client role.
  -- Pure function of its argument; reveals nothing.
  public.receipt_group_id(text)
to authenticated;
