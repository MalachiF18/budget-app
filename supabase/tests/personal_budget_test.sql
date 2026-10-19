-- Run after all migrations, against a disposable/local Supabase database.
-- Every fixture is rolled back. ON_ERROR_STOP makes a failure fail the command.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id, aud, role, raw_app_meta_data, raw_user_meta_data)
values ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'authenticated', 'authenticated', '{}', '{}'),
       ('ffffffff-ffff-4fff-8fff-ffffffffffff', 'authenticated', 'authenticated', '{}', '{}');
set local role authenticated;
set local request.jwt.claims = '{"sub":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","role":"authenticated"}';
select public.save_personal_budget(100000, 'fixed', 10000, '2026-09-01',
  '[{"kind":"one_time","name":"September","amount_cents":900}]');
select public.save_personal_budget(100000, 'percent', 10, '2026-10-01',
  '[{"kind":"bill","name":"Rent","amount_cents":40000},
    {"kind":"one_time","name":"October","amount_cents":1000}]');
do $$
declare b uuid;
begin
  select id into strict b from public.budgets;
  if (select count(*) from public.budget_items where budget_id = b) <> 3 then
    raise exception 'Other-month items were not preserved';
  end if;
  -- Invalid item aborts the entire save, including budget changes and deletes.
  begin
    perform public.save_personal_budget(200000, 'fixed', 0, '2026-10-01',
      '[{"kind":"bill","name":"Invalid","amount_cents":-1}]');
    raise exception 'Expected constraint violation';
  exception when check_violation then null;
  end;
  if (select earnings_cents from public.budgets where id = b) <> 100000
     or (select count(*) from public.budget_items where budget_id = b) <> 3 then
    raise exception 'Save failure was not atomic';
  end if;
end;
$$;
select public.save_personal_budget(100000, 'fixed', 5000, '2026-10-01', '[]');
do $$
begin
  if (select count(*) from public.budget_items) <> 1
     or (select name from public.budget_items) <> 'September' then
    raise exception 'Removing current-month items changed another month';
  end if;
end;
$$;
set local request.jwt.claims = '{"sub":"ffffffff-ffff-4fff-8fff-ffffffffffff","role":"authenticated"}';
do $$
begin
  if exists(select 1 from public.budgets) or exists(select 1 from public.budget_items) then
    raise exception 'Another user can read the budget';
  end if;
end;
$$;
select public.save_personal_budget(500, 'fixed', 0, '2026-10-01', '[]');
set local request.jwt.claims = '{"sub":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee","role":"authenticated"}';
do $$
begin
  if (select earnings_cents from public.budgets) <> 100000 then
    raise exception 'Another user changed the original budget';
  end if;
end;
$$;
rollback;
