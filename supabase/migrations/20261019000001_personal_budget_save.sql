-- Save one complete edit atomically; a failure leaves the previous budget intact.
-- SECURITY INVOKER keeps all existing owner-only RLS policies in force.
create function public.save_personal_budget(
  p_earnings bigint, p_savings_mode text, p_savings_value bigint,
  p_month date, p_items jsonb
) returns void language plpgsql security invoker set search_path = '' as $$
declare
  v_budget uuid;
begin
  if auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;
  if p_month is null or p_month <> date_trunc('month', p_month)::date
     or p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'Invalid month or items' using errcode = '22023';
  end if;
  insert into public.budgets(user_id, earnings_cents, savings_mode, savings_value)
    values (auth.uid(), p_earnings, p_savings_mode, p_savings_value)
    on conflict (user_id) do update set earnings_cents = excluded.earnings_cents,
      savings_mode = excluded.savings_mode, savings_value = excluded.savings_value,
      updated_at = now()
    returning id into v_budget;
  delete from public.budget_items where budget_id = v_budget
    and (kind <> 'one_time' or month = p_month);
  insert into public.budget_items(budget_id, kind, name, amount_cents, month)
    select v_budget, i.kind, i.name, i.amount_cents,
      case when i.kind = 'one_time' then p_month else null end
    from jsonb_to_recordset(p_items) as i(kind text, name text, amount_cents bigint);
end;
$$;
revoke all on function public.save_personal_budget(bigint, text, bigint, date, jsonb)
  from public, anon, authenticated;
grant execute on function public.save_personal_budget(bigint, text, bigint, date, jsonb)
  to authenticated;
