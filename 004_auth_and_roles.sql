-- =========================================================
-- 004_auth_and_roles.sql
-- Links each login to a role, and upgrades every table's lock
-- from "any logged-in user" to "only staff", with pricing
-- reserved for the owner.
-- =========================================================

create table staff (
  id         uuid primary key references auth.users (id) on delete cascade,
  email      text,
  role       text not null check (role in ('owner', 'cashier')),
  created_at timestamptz not null default now()
);

insert into staff (id, email, role)
select id, email, 'owner'   from auth.users where email = 'ziyan47@gmail.com';

insert into staff (id, email, role)
select id, email, 'cashier' from auth.users where email = 'jenintradehouse@gmail.com';

create or replace function is_staff()
returns boolean language sql security definer set search_path = public as $$
  select exists (select 1 from staff where id = auth.uid());
$$;

create or replace function is_owner()
returns boolean language sql security definer set search_path = public as $$
  select exists (select 1 from staff where id = auth.uid() and role = 'owner');
$$;

alter table staff enable row level security;
create policy "Read own staff row" on staff for select to authenticated using (id = auth.uid());

drop policy "Staff read sessions"   on sessions;
drop policy "Staff create sessions" on sessions;
drop policy "Staff update sessions" on sessions;
create policy "Staff read sessions"   on sessions for select to authenticated using (is_staff());
create policy "Staff create sessions" on sessions for insert to authenticated with check (is_staff());
create policy "Staff update sessions" on sessions for update to authenticated using (is_staff()) with check (is_staff());

drop policy "Staff read segments"   on session_segments;
drop policy "Staff create segments" on session_segments;
drop policy "Staff update segments" on session_segments;
create policy "Staff read segments"   on session_segments for select to authenticated using (is_staff());
create policy "Staff create segments" on session_segments for insert to authenticated with check (is_staff());
create policy "Staff update segments" on session_segments for update to authenticated using (is_staff()) with check (is_staff());

drop policy "Staff read settings" on settings;
create policy "Staff read settings"  on settings for select to authenticated using (is_staff());
create policy "Owner can update settings" on settings for update to authenticated using (is_owner()) with check (is_owner());

select email, role from staff order by role;
