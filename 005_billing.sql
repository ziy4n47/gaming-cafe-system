-- =========================================================
-- 005_billing.sql
-- Billing runs on the SERVER. The browser can only ASK to end
-- a session; the database computes minutes, applies the
-- recurring free-time discount, and writes the amount.
-- =========================================================

-- 1. PURE MATH: given a number of minutes, what's the charge?
--    Single source of truth for the discount rule. Reads the
--    rate + block sizes from settings, so changing the price
--    later needs no code change.
create or replace function preview_charge(p_minutes int)
returns table (total_minutes int, chargeable_minutes int, discount_minutes int, amount numeric)
language plpgsql security definer set search_path = public as $$
declare
  v_rate numeric; v_charge int; v_free int; v_cycle int;
  v_full int; v_left int; v_ch int;
begin
  select rate_per_minute, charge_block_minutes, free_block_minutes
    into v_rate, v_charge, v_free from settings where id = 1;
  v_cycle := v_charge + v_free;                       -- 300 + 60 = 360
  v_full  := floor(p_minutes::numeric / v_cycle);     -- whole 360-min cycles
  v_left  := p_minutes - (v_full * v_cycle);          -- leftover minutes
  v_ch    := v_full * v_charge + least(v_left, v_charge);
  return query select p_minutes, v_ch, (p_minutes - v_ch), (v_ch * v_rate)::numeric;
end; $$;

-- 2. END A SESSION: close segments, total the minutes across the
--    whole visit (covers PC switches), bill walk-ins, store it all.
create or replace function end_session(p_session_id bigint)
returns table (total_minutes int, chargeable_minutes int, discount_minutes int, amount numeric)
language plpgsql security definer set search_path = public as $$
declare
  v_now timestamptz := now();
  v_is_member boolean;
  v_total int; v_ch int; v_disc int; v_amount numeric; v_rate numeric;
begin
  if not is_staff() then raise exception 'Not authorised'; end if;

  select (customer_type = 'member') into v_is_member
    from sessions where id = p_session_id and ended_at is null;
  if not found then raise exception 'Session not found or already closed'; end if;

  -- close any open segment at SERVER time (not the browser's clock)
  update session_segments set ended_at = v_now
    where session_id = p_session_id and ended_at is null;

  -- total minutes = sum of every stretch in this visit
  select floor(coalesce(sum(extract(epoch from (ended_at - started_at))), 0) / 60.0)::int
    into v_total from session_segments where session_id = p_session_id;

  if v_is_member then
    update sessions set ended_at = v_now where id = p_session_id;
    return query select v_total, null::int, null::int, null::numeric;
    return;
  end if;

  select p.chargeable_minutes, p.discount_minutes, p.amount
    into v_ch, v_disc, v_amount from preview_charge(v_total) p;
  select rate_per_minute into v_rate from settings where id = 1;

  update sessions set
    ended_at = v_now, billed_at = v_now, rate_per_minute = v_rate,
    total_minutes = v_total, chargeable_minutes = v_ch,
    discount_minutes = v_disc, amount = v_amount
    where id = p_session_id;

  return query select v_total, v_ch, v_disc, v_amount;
end; $$;

grant execute on function preview_charge(int)    to authenticated;
grant execute on function end_session(bigint)    to authenticated;

-- 3. Lock a session once it's closed: cashiers can only edit OPEN
--    sessions. After billing, the row is frozen (the billing
--    function itself bypasses this, so it can still close them).
drop policy "Staff update sessions" on sessions;
create policy "Staff update sessions" on sessions
  for update to authenticated
  using (is_staff() and ended_at is null)
  with check (is_staff());
