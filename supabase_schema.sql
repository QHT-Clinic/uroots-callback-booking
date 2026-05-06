-- ============================================================
-- URoots — Callback Bookings schema
-- Run this in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================

-- Main bookings table
create table if not exists public.callback_bookings (
  id              uuid          primary key default gen_random_uuid(),
  created_at      timestamptz   not null default now(),
  updated_at      timestamptz   not null default now(),

  -- Customer details
  full_name       text          not null,
  phone           text          not null,            -- formatted: +919876543210
  phone_raw       text          not null,            -- 10-digit:  9876543210
  language        text          not null default 'Hindi',

  -- Schedule
  call_date       date          not null,
  call_time       time          not null,
  call_time_label text,                              -- "10.30 am"
  call_period     text          not null,            -- morning | afternoon | evening

  -- Workflow status
  status          text          not null default 'pending',
  contacted_at    timestamptz,
  agent_notes     text,

  -- Submission metadata
  source          text,
  timezone        text,
  user_agent      text,
  referrer        text,
  page_url        text,

  -- Constraints
  constraint phone_format  check (phone_raw  ~ '^[6-9][0-9]{9}$'),
  constraint period_valid  check (call_period in ('morning', 'afternoon', 'evening')),
  constraint status_valid  check (status      in ('pending', 'contacted', 'completed', 'no_show', 'cancelled'))
);

-- ============================================================
-- Indexes for fast lookups
-- ============================================================
create index if not exists idx_bookings_call_datetime on public.callback_bookings (call_date, call_time);
create index if not exists idx_bookings_phone         on public.callback_bookings (phone_raw);
create index if not exists idx_bookings_status        on public.callback_bookings (status);
create index if not exists idx_bookings_created_desc  on public.callback_bookings (created_at desc);

-- ============================================================
-- Auto-update `updated_at` on every row change
-- ============================================================
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_bookings_updated_at on public.callback_bookings;
create trigger trg_bookings_updated_at
  before update on public.callback_bookings
  for each row execute function public.touch_updated_at();

-- ============================================================
-- Row Level Security
-- ============================================================
alter table public.callback_bookings enable row level security;

-- Anyone (anon key) can INSERT a booking — needed if frontend POSTs directly
drop policy if exists "anon can insert bookings" on public.callback_bookings;
create policy "anon can insert bookings"
  on public.callback_bookings
  for insert
  to anon
  with check (true);

-- Only logged-in dashboard users can READ
drop policy if exists "authenticated can read bookings" on public.callback_bookings;
create policy "authenticated can read bookings"
  on public.callback_bookings
  for select
  to authenticated
  using (true);

-- Only authenticated users can UPDATE (e.g., agents marking contacted)
drop policy if exists "authenticated can update bookings" on public.callback_bookings;
create policy "authenticated can update bookings"
  on public.callback_bookings
  for update
  to authenticated
  using (true)
  with check (true);

-- ============================================================
-- Helpful views
-- ============================================================

-- Today's pending callbacks, sorted by time
create or replace view public.todays_callbacks as
select id, created_at, full_name, phone, language, call_time, call_time_label, call_period, status
from public.callback_bookings
where call_date = current_date
  and status    = 'pending'
order by call_time;

-- Daily booking counts (last 30 days)
create or replace view public.bookings_daily_count as
select
  call_date,
  count(*)                                              as total,
  count(*) filter (where status = 'pending')            as pending,
  count(*) filter (where status = 'contacted')          as contacted,
  count(*) filter (where status = 'completed')          as completed
from public.callback_bookings
where call_date >= current_date - interval '30 days'
group by call_date
order by call_date desc;

-- ============================================================
-- Sample manual insert (for testing)
-- ============================================================
-- insert into public.callback_bookings
--   (full_name, phone, phone_raw, language, call_date, call_time, call_time_label, call_period, source)
-- values
--   ('Test User', '+919999999999', '9999999999', 'Hindi', current_date, '10:30', '10.30 am', 'morning', 'manual-test');
