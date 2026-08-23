-- =========================================================
-- 003_pricing.sql
-- Rate + discount rule live in ONE editable row (settings),
-- so the OWNER can change them from their interface later.
-- Each walk-in session's billed result is snapshotted onto
-- the session at close.
-- =========================================================

create table settings (
  id                   int primary key default 1,
  rate_per_minute      numeric(10,2) not null default 1.00,
  charge_block_minutes int not null default 300,
  free_block_minutes   int not null default 60,
  updated_at           timestamptz not null default now(),
  constraint settings_single_row check (id = 1)
);

insert into settings (id) values (1);

alter table settings enable row level security;

create policy "Staff read settings"
  on settings for select to authenticated using (true);

alter table sessions
  add column rate_per_minute    numeric(10,2),
  add column total_minutes      int,
  add column chargeable_minutes int,
  add column discount_minutes   int,
  add column amount             numeric(10,2),
  add column billed_at          timestamptz;
