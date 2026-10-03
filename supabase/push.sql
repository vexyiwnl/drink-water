-- Milestone 5: phones that should get a silent "sync" push when data changes.
-- Run once in Supabase → SQL Editor (after schema.sql).

create table public.devices (
  token text primary key,                    -- FCM registration token
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  updated_at timestamptz not null default now()
);

alter table public.devices enable row level security;

create policy "own devices" on public.devices for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
