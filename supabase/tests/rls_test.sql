-- RLS and RPC checks for the budget-app database.
--
-- HOW TO RUN: apply the four migrations first, then paste this whole file
-- into the Supabase dashboard SQL editor and press Run (or `psql -f`).
--
-- WHAT YOU WILL SEE: the script ALWAYS ends with an ERROR on purpose. The
-- error message is the report, e.g.
--   RLS TEST REPORT: 24 passed, 0 failed (everything rolled back)
--   PASS 01 ...
-- Ending in an error is what guarantees nothing is saved: the test users,
-- group, expenses and payments all disappear with the rollback. If the
-- message is anything other than "RLS TEST REPORT", setup itself broke;
-- read that error.
--
-- HOW IT SIMULATES USERS: exactly what PostgREST does for an app request:
--   set local role authenticated;
--   set local request.jwt.claims = '{"sub":"<user id>","role":"authenticated"}';
-- then calls the same public.* functions / selects the same tables the app
-- will. `reset role` goes back to the editor's own (postgres) role.
--
-- Every "cannot" check also has a control showing the SAME query does work
-- for someone allowed, so a zero-row result cannot pass vacuously, and
-- expected errors are matched on their message, so an unrelated error
-- (typo, missing function) is a FAIL, not a PASS.
--
-- PROVING THE CHECKS CAN FAIL: a check nobody has seen fail is not known to
-- work. To watch one go red, add this line right after `begin;` below:
--   create policy "mutant" on public.budgets for select to authenticated using (true);
-- and run again: check 18 must report FAIL (B can read A's budget). Remove
-- the line afterwards (it is rolled back either way).
--
-- Test users (fixed ids, rolled back at the end):
--   A aaaaaaaa-...  creates the group, adds the expense, receives payment
--   B bbbbbbbb-...  member, owes A (the payer)
--   C cccccccc-...  member
--   D dddddddd-...  outsider, never joins

begin;

-- Report accumulator. A custom setting rather than a table, so every role
-- can append to it and it needs no grants.
select set_config('t.report', '', true);

-- ---------------------------------------------------------------- fixtures
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data,
                        raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
   'authenticated', 'authenticated', 'rls-test-a@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
   'authenticated', 'authenticated', 'rls-test-b@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
   'authenticated', 'authenticated', 'rls-test-c@example.test', '{}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
   'authenticated', 'authenticated', 'rls-test-d@example.test', '{}', '{}', now(), now());

-- ============================================================ as A
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}';

-- 01: a user creates their own profile through RLS, then creates a group;
--     the sync code is 12 chars from the no-look-alike alphabet.
do $$
declare r record;
begin
  insert into public.profiles (id, display_name)
    values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Alice');
  select * into r from public.create_group('Test house');
  perform set_config('t.group', r.group_id::text, true);
  perform set_config('t.code', r.sync_code, true);
  if r.sync_code ~ '^[A-HJKMNP-Z2-9]{12}$' then
    perform set_config('t.report', current_setting('t.report') || E'\nPASS 01 create_group returned a 12-char code: ' || r.sync_code, true);
  else
    perform set_config('t.report', current_setting('t.report') || E'\nFAIL 01 bad sync code: ' || coalesce(r.sync_code, 'NULL'), true);
  end if;
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 01 setup error: ' || sqlerrm, true);
end $$;

-- 02: a user cannot create a profile for somebody else.
do $$
begin
  begin
    insert into public.profiles (id, display_name)
      values ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'Impostor');
    perform set_config('t.report', current_setting('t.report') || E'\nFAIL 02 A created a profile for D', true);
  exception when others then
    if sqlstate = '42501' then
      perform set_config('t.report', current_setting('t.report') || E'\nPASS 02 cannot create another user''s profile', true);
    else
      perform set_config('t.report', current_setting('t.report') || E'\nFAIL 02 unexpected error: ' || sqlerrm, true);
    end if;
  end;
end $$;

-- ============================================================ as B
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}';

-- 03: join normalises input: lowercase with a dash and a space still works.
do $$
declare v_code text := current_setting('t.code'); v_got uuid;
begin
  insert into public.profiles (id, display_name)
    values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Bob');
  v_got := public.join_group(lower(substr(v_code, 1, 4) || '-' || substr(v_code, 5, 4) || ' ' || substr(v_code, 9, 4)));
  if v_got = current_setting('t.group')::uuid and public.is_group_member(v_got) then
    perform set_config('t.report', current_setting('t.report') || E'\nPASS 03 join_group accepts lowercase/dashed/spaced code', true);
  else
    perform set_config('t.report', current_setting('t.report') || E'\nFAIL 03 join returned ' || coalesce(v_got::text, 'NULL'), true);
  end if;
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 03 error: ' || sqlerrm, true);
end $$;

-- ============================================================ as C
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","role":"authenticated"}';

do $$
begin
  insert into public.profiles (id, display_name)
    values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'Carol');
  if public.join_group(current_setting('t.code')) = current_setting('t.group')::uuid then
    perform set_config('t.report', current_setting('t.report') || E'\nPASS 04 third member joins with the plain code', true);
  else
    perform set_config('t.report', current_setting('t.report') || E'\nFAIL 04 C could not join', true);
  end if;
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 04 error: ' || sqlerrm, true);
end $$;

-- ============================================================ as D (outsider)
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"dddddddd-dddd-4ddd-8ddd-dddddddddddd","role":"authenticated"}';

-- 05: a well-formed but wrong code returns NULL and does not make D a member.
do $$
declare
  v_wrong text := case when current_setting('t.code') = 'ZZZZZZZZZZZZ'
                       then 'YYYYYYYYYYYY' else 'ZZZZZZZZZZZZ' end;
  v_got uuid;
begin
  insert into public.profiles (id, display_name)
    values ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'Dave');
  v_got := public.join_group(v_wrong);
  if v_got is null and not public.is_group_member(current_setting('t.group')::uuid) then
    perform set_config('t.report', current_setting('t.report') || E'\nPASS 05 wrong code returns NULL, no membership', true);
  else
    perform set_config('t.report', current_setting('t.report') || E'\nFAIL 05 wrong code returned ' || coalesce(v_got::text, 'NULL'), true);
  end if;
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 05 error: ' || sqlerrm, true);
end $$;

-- 06: outsider cannot add themself by writing group_members directly.
do $$
begin
  begin
    insert into public.group_members (group_id, user_id)
      values (current_setting('t.group')::uuid, 'dddddddd-dddd-4ddd-8ddd-dddddddddddd');
    perform set_config('t.report', current_setting('t.report') || E'\nFAIL 06 direct insert into group_members was ACCEPTED', true);
  exception when others then
    if sqlstate = '42501' then
      perform set_config('t.report', current_setting('t.report') || E'\nPASS 06 direct group_members insert: permission denied', true);
    else
      perform set_config('t.report', current_setting('t.report') || E'\nFAIL 06 unexpected error: ' || sqlerrm, true);
    end if;
  end;
end $$;

-- ============================================================ as A
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}';

-- 07: valid expense, $30.00 split three ways.
do $$
declare v_id uuid;
begin
  v_id := public.add_expense(
    p_group_id := current_setting('t.group')::uuid,
    p_description := 'Groceries',
    p_amount_cents := 3000,
    p_shares := '[{"user_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","share_cents":1000},
                  {"user_id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","share_cents":1000},
                  {"user_id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","share_cents":1000}]'::jsonb);
  perform set_config('t.expense', v_id::text, true);
  if (select count(*) from public.expense_shares where expense_id = v_id) = 3 then
    perform set_config('t.report', current_setting('t.report') || E'\nPASS 07 add_expense with shares summing to amount', true);
  else
    perform set_config('t.report', current_setting('t.report') || E'\nFAIL 07 expense saved without its 3 shares', true);
  end if;
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 07 error: ' || sqlerrm, true);
end $$;

-- 08: shares that do not add up are rejected.
do $$
begin
  begin
    perform public.add_expense(
      p_group_id := current_setting('t.group')::uuid,
      p_description := 'Off by a cent',
      p_amount_cents := 3000,
      p_shares := '[{"user_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","share_cents":1000},
                    {"user_id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","share_cents":1999}]'::jsonb);
    perform set_config('t.report', current_setting('t.report') || E'\nFAIL 08 shares summing to 2999 of 3000 were ACCEPTED', true);
  exception when others then
    if sqlerrm like 'Shares must add up%' then
      perform set_config('t.report', current_setting('t.report') || E'\nPASS 08 shares not summing to amount rejected', true);
    else
      perform set_config('t.report', current_setting('t.report') || E'\nFAIL 08 unexpected error: ' || sqlerrm, true);
    end if;
  end;
end $$;

-- 09: cannot charge someone outside the group.
do $$
begin
  begin
    perform public.add_expense(
      p_group_id := current_setting('t.group')::uuid,
      p_description := 'Charge a stranger',
      p_amount_cents := 500,
      p_shares := '[{"user_id":"dddddddd-dddd-4ddd-8ddd-dddddddddddd","share_cents":500}]'::jsonb);
    perform set_config('t.report', current_setting('t.report') || E'\nFAIL 09 non-member share was ACCEPTED', true);
  exception when others then
    if sqlerrm like 'Every person charged must be a member%' then
      perform set_config('t.report', current_setting('t.report') || E'\nPASS 09 share for non-member rejected', true);
    else
      perform set_config('t.report', current_setting('t.report') || E'\nFAIL 09 unexpected error: ' || sqlerrm, true);
    end if;
  end;
end $$;

-- 10: receipt path must sit under THIS group's folder.
do $$
begin
  begin
    perform public.add_expense(
      p_group_id := current_setting('t.group')::uuid,
      p_description := 'Receipt in wrong folder',
      p_amount_cents := 100,
      p_shares := '[{"user_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","share_cents":100}]'::jsonb,
      p_receipt_path := '00000000-0000-4000-8000-000000000000/11111111-1111-4111-8111-111111111111.jpg');
    perform set_config('t.report', current_setting('t.report') || E'\nFAIL 10 receipt path for another group was ACCEPTED', true);
  exception when others then
    if sqlerrm like 'Receipt path must be%' then
      perform set_config('t.report', current_setting('t.report') || E'\nPASS 10 receipt path outside the group folder rejected', true);
    else
      perform set_config('t.report', current_setting('t.report') || E'\nFAIL 10 unexpected error: ' || sqlerrm, true);
    end if;
  end;
end $$;

-- 11: control for 10: a correct receipt path is accepted.
do $$
declare v_id uuid;
begin
  v_id := public.add_expense(
    p_group_id := current_setting('t.group')::uuid,
    p_description := 'With receipt',
    p_amount_cents := 100,
    p_shares := '[{"user_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","share_cents":100}]'::jsonb,
    p_receipt_path := current_setting('t.group') || '/11111111-1111-4111-8111-111111111111.webp');
  perform set_config('t.report', current_setting('t.report') || E'\nPASS 11 valid receipt path accepted', true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 11 error: ' || sqlerrm, true);
end $$;

-- 12: A records that B paid A $10.00 (A is the receiver: allowed).
do $$
declare v_id uuid; r record;
begin
  v_id := public.record_payment(current_setting('t.group')::uuid,
                                'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 1000);
  perform set_config('t.payment', v_id::text, true);
  select * into r from public.payments where id = v_id;
  if r.to_user = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and r.recorded_by = r.to_user
     and r.from_user = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' then
    perform set_config('t.report', current_setting('t.report') || E'\nPASS 12 receiver records payment (to_user = recorded_by = caller)', true);
  else
    perform set_config('t.report', current_setting('t.report') || E'\nFAIL 12 payment row has wrong parties', true);
  end if;
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 12 error: ' || sqlerrm, true);
end $$;

-- 13: personal data. A writes own budget directly through RLS.
do $$
begin
  insert into public.budgets (earnings_cents, savings_mode, savings_value)
    values (250000, 'percent', 10);
  if (select count(*) from public.budgets) = 1 then
    perform set_config('t.report', current_setting('t.report') || E'\nPASS 13 owner writes and reads own budget', true);
  else
    perform set_config('t.report', current_setting('t.report') || E'\nFAIL 13 owner cannot see own budget', true);
  end if;
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 13 error: ' || sqlerrm, true);
end $$;

-- ============================================================ as B
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}';

-- 14: members CAN read the group's data. This is also the control arm for
--     the outsider check (18): same queries, must be non-zero here.
do $$
declare g uuid := current_setting('t.group')::uuid; n_g int; n_m int; n_e int; n_s int; n_p int; n_prof int;
begin
  select count(*) into n_g from public.groups where id = g;
  select count(*) into n_m from public.group_members where group_id = g;
  select count(*) into n_e from public.expenses where group_id = g;
  select count(*) into n_s from public.expense_shares s join public.expenses e on e.id = s.expense_id where e.group_id = g;
  select count(*) into n_p from public.payments where group_id = g;
  select count(*) into n_prof from public.profiles where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  if n_g = 1 and n_m = 3 and n_e >= 1 and n_s >= 3 and n_p = 1 and n_prof = 1 then
    perform set_config('t.report', current_setting('t.report') || E'\nPASS 14 member reads group, members, expenses, shares, payments, co-member profile', true);
  else
    perform set_config('t.report', current_setting('t.report') || format(E'\nFAIL 14 member counts g=%s m=%s e=%s s=%s p=%s prof=%s', n_g, n_m, n_e, n_s, n_p, n_prof), true);
  end if;
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 14 error: ' || sqlerrm, true);
end $$;

-- 15: non-creator cannot update the expense, and it is unchanged after.
do $$
declare v_amount bigint;
begin
  begin
    perform public.update_expense(
      p_expense_id := current_setting('t.expense')::uuid,
      p_description := 'Hijacked',
      p_amount_cents := 1,
      p_occurred_on := current_date,
      p_shares := '[{"user_id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","share_cents":1}]'::jsonb);
    perform set_config('t.report', current_setting('t.report') || E'\nFAIL 15 non-creator update was ACCEPTED', true);
  exception when others then
    select amount_cents into v_amount from public.expenses where id = current_setting('t.expense')::uuid;
    if sqlerrm like 'Only the person who added this expense%' and v_amount = 3000 then
      perform set_config('t.report', current_setting('t.report') || E'\nPASS 15 non-creator update rejected, amount still 3000', true);
    else
      perform set_config('t.report', current_setting('t.report') || E'\nFAIL 15 unexpected: ' || sqlerrm || ' amount=' || coalesce(v_amount::text, 'NULL'), true);
    end if;
  end;
end $$;

-- 16: non-creator cannot delete it (RPC), nor update it directly.
do $$
begin
  begin
    perform public.delete_expense(current_setting('t.expense')::uuid);
    perform set_config('t.report', current_setting('t.report') || E'\nFAIL 16 non-creator delete was ACCEPTED', true);
  exception when others then
    if sqlerrm like 'Only the person who added this expense%'
       and exists (select 1 from public.expenses where id = current_setting('t.expense')::uuid) then
      perform set_config('t.report', current_setting('t.report') || E'\nPASS 16 non-creator delete rejected, expense still there', true);
    else
      perform set_config('t.report', current_setting('t.report') || E'\nFAIL 16 unexpected error: ' || sqlerrm, true);
    end if;
  end;
  begin
    update public.expenses set amount_cents = 1 where id = current_setting('t.expense')::uuid;
    perform set_config('t.report', current_setting('t.report') || E'\nFAIL 16b direct UPDATE on expenses was ACCEPTED', true);
  exception when others then
    if sqlstate = '42501' then
      perform set_config('t.report', current_setting('t.report') || E'\nPASS 16b direct UPDATE on expenses: permission denied', true);
    else
      perform set_config('t.report', current_setting('t.report') || E'\nFAIL 16b unexpected error: ' || sqlerrm, true);
    end if;
  end;
end $$;

-- 17: the payer (B) cannot record a payment: not through the RPC (the
--     caller is always the receiver, so "from B" by B is from = to), and not
--     by writing payments directly; nor can B delete A's received payment.
do $$
begin
  begin
    perform public.record_payment(current_setting('t.group')::uuid,
                                  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 1000);
    perform set_config('t.report', current_setting('t.report') || E'\nFAIL 17 payer recorded own payment via RPC', true);
  exception when others then
    if sqlerrm like 'Only the person who received the money%' then
      perform set_config('t.report', current_setting('t.report') || E'\nPASS 17 payer cannot record payment via RPC', true);
    else
      perform set_config('t.report', current_setting('t.report') || E'\nFAIL 17 unexpected error: ' || sqlerrm, true);
    end if;
  end;
  begin
    insert into public.payments (group_id, from_user, to_user, amount_cents, recorded_by)
      values (current_setting('t.group')::uuid, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
              'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 1000, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    perform set_config('t.report', current_setting('t.report') || E'\nFAIL 17b direct INSERT into payments was ACCEPTED', true);
  exception when others then
    if sqlstate = '42501' then
      perform set_config('t.report', current_setting('t.report') || E'\nPASS 17b direct payments insert: permission denied', true);
    else
      perform set_config('t.report', current_setting('t.report') || E'\nFAIL 17b unexpected error: ' || sqlerrm, true);
    end if;
  end;
  begin
    perform public.delete_payment(current_setting('t.payment')::uuid);
    perform set_config('t.report', current_setting('t.report') || E'\nFAIL 17c payer deleted the receiver''s payment', true);
  exception when others then
    if sqlerrm like 'Only the person who received this payment%' then
      perform set_config('t.report', current_setting('t.report') || E'\nPASS 17c payer cannot delete the payment', true);
    else
      perform set_config('t.report', current_setting('t.report') || E'\nFAIL 17c unexpected error: ' || sqlerrm, true);
    end if;
  end;
end $$;

-- 18: B cannot read A's personal budget (control: 13, A sees 1 row).
do $$
begin
  if (select count(*) from public.budgets where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') = 0 then
    perform set_config('t.report', current_setting('t.report') || E'\nPASS 18 other users cannot read a personal budget', true);
  else
    perform set_config('t.report', current_setting('t.report') || E'\nFAIL 18 B can read A''s budget', true);
  end if;
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 18 error: ' || sqlerrm, true);
end $$;

-- ============================================================ as D (outsider)
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"dddddddd-dddd-4ddd-8ddd-dddddddddddd","role":"authenticated"}';

-- 19: outsider sees nothing of the group (same queries as 14).
do $$
declare g uuid := current_setting('t.group')::uuid; n_g int; n_m int; n_e int; n_s int; n_p int; n_prof int;
begin
  select count(*) into n_g from public.groups where id = g;
  select count(*) into n_m from public.group_members where group_id = g;
  select count(*) into n_e from public.expenses where group_id = g;
  select count(*) into n_s from public.expense_shares where expense_id = current_setting('t.expense')::uuid;
  select count(*) into n_p from public.payments where group_id = g;
  select count(*) into n_prof from public.profiles where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  if n_g + n_m + n_e + n_s + n_p + n_prof = 0 then
    perform set_config('t.report', current_setting('t.report') || E'\nPASS 19 outsider reads 0 rows of group, members, expenses, shares, payments, profiles', true);
  else
    perform set_config('t.report', current_setting('t.report') || format(E'\nFAIL 19 outsider counts g=%s m=%s e=%s s=%s p=%s prof=%s', n_g, n_m, n_e, n_s, n_p, n_prof), true);
  end if;
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 19 error: ' || sqlerrm, true);
end $$;

-- 20: brute-force friction. D already has 1 failed attempt (05). Nine more
--     wrong codes return NULL; the next call is refused, and stays refused
--     even with the CORRECT code (the throttle runs before the lookup).
do $$
declare
  v_wrong text := case when current_setting('t.code') = 'ZZZZZZZZZZZZ'
                       then 'YYYYYYYYYYYY' else 'ZZZZZZZZZZZZ' end;
  i int;
  v_refused_at int;
begin
  for i in 2 .. 15 loop
    begin
      perform public.join_group(v_wrong);
    exception when others then
      if sqlerrm like 'Too many wrong codes%' then v_refused_at := i; exit; end if;
      raise;
    end;
  end loop;
  begin
    perform public.join_group(current_setting('t.code'));
    perform set_config('t.report', current_setting('t.report') || E'\nFAIL 20 throttled user still joined with the right code', true);
  exception when others then
    if v_refused_at = 11 and sqlerrm like 'Too many wrong codes%' then
      perform set_config('t.report', current_setting('t.report') || E'\nPASS 20 11th attempt refused after 10 wrong codes, even with the right code', true);
    else
      perform set_config('t.report', current_setting('t.report') || E'\nFAIL 20 refused_at=' || coalesce(v_refused_at::text, 'never') || ' last error: ' || sqlerrm, true);
    end if;
  end;
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 20 error: ' || sqlerrm, true);
end $$;

-- ============================================================ as A
reset role;
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}';

-- 21: the creator can update (shares replaced) and then delete.
do $$
declare v_id uuid := current_setting('t.expense')::uuid; n int;
begin
  perform public.update_expense(
    p_expense_id := v_id,
    p_description := 'Groceries (fixed)',
    p_amount_cents := 2001,
    p_occurred_on := current_date,
    p_shares := '[{"user_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","share_cents":1001},
                  {"user_id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","share_cents":1000}]'::jsonb);
  select count(*) into n from public.expense_shares where expense_id = v_id;
  if n <> 2 then
    perform set_config('t.report', current_setting('t.report') || E'\nFAIL 21 shares not replaced, count=' || n, true);
  else
    perform public.delete_expense(v_id);
    if exists (select 1 from public.expenses where id = v_id) then
      perform set_config('t.report', current_setting('t.report') || E'\nFAIL 21 creator delete left the expense', true);
    else
      perform set_config('t.report', current_setting('t.report') || E'\nPASS 21 creator updates (shares replaced) and deletes own expense', true);
    end if;
  end if;
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 21 error: ' || sqlerrm, true);
end $$;

-- 22: the receiver can delete the payment they recorded.
do $$
begin
  perform public.delete_payment(current_setting('t.payment')::uuid);
  perform set_config('t.report', current_setting('t.report') || E'\nPASS 22 receiver deletes own recorded payment', true);
exception when others then
  perform set_config('t.report', current_setting('t.report') || E'\nFAIL 22 error: ' || sqlerrm, true);
end $$;

-- ============================================================ as anon (not signed in)
reset role;
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

-- 23: a client that has not signed in can neither read nor call the API.
do $$
declare v_read text; v_call text;
begin
  begin
    perform count(*) from public.groups;
    v_read := 'allowed';
  exception when others then v_read := sqlstate;
  end;
  begin
    perform public.create_group('Anon group');
    v_call := 'allowed';
  exception when others then v_call := sqlstate;
  end;
  if v_read = '42501' and v_call = '42501' then
    perform set_config('t.report', current_setting('t.report') || E'\nPASS 23 anon: no table read, no RPC execute', true);
  else
    perform set_config('t.report', current_setting('t.report') || E'\nFAIL 23 anon read=' || v_read || ' call=' || v_call, true);
  end if;
end $$;

-- ============================================================ as postgres
reset role;

-- 24: COMPONENT test of the deferred backstop trigger, bypassing the RPCs
--     (as an admin or a future function might). Forces the deferred check
--     to run now instead of at commit.
do $$
declare v_id uuid := gen_random_uuid();
begin
  begin
    insert into public.expenses (id, group_id, paid_by, created_by, description, amount_cents)
      values (v_id, current_setting('t.group')::uuid,
              'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
              'Direct insert', 500);
    insert into public.expense_shares (expense_id, user_id, share_cents)
      values (v_id, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 499);
    set constraints public.expense_shares_sum_check, public.expenses_shares_sum_check immediate;
    perform set_config('t.report', current_setting('t.report') || E'\nFAIL 24 trigger let 499 of 500 through', true);
  exception when others then
    -- Match the exact numbers: SET CONSTRAINTS also fires the checks queued
    -- by earlier tests' RPC writes, and a failure there must not pass as this.
    if sqlerrm = 'Shares must add up to the expense amount (499 <> 500)' then
      perform set_config('t.report', current_setting('t.report') || E'\nPASS 24 deferred trigger rejects shares not summing to amount', true);
    else
      perform set_config('t.report', current_setting('t.report') || E'\nFAIL 24 unexpected error: ' || sqlerrm, true);
    end if;
  end;
end $$;

-- ---------------------------------------------------------------- report
-- Raises on purpose: shows the report and rolls everything back.
do $$
declare
  v_report text := current_setting('t.report');
  v_pass int := (select count(*) from regexp_matches(v_report, E'\\nPASS', 'g'));
  v_fail int := (select count(*) from regexp_matches(v_report, E'\\nFAIL', 'g'));
begin
  raise exception E'RLS TEST REPORT: % passed, % failed (everything rolled back)%',
    v_pass, v_fail, v_report;
end $$;

rollback;
