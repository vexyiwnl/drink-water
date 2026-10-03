-- Drink Water: tables, row-level security, last-write-wins sync, realtime.
-- Run once in Supabase → SQL Editor → New query.

create table public.day_sessions (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  started_at timestamptz not null,
  ended_at timestamptz,
  goal_ml int not null check (goal_ml > 0),
  updated_at timestamptz not null,          -- when the device made the change (LWW)
  deleted boolean not null default false,   -- soft delete, so deletes sync too
  server_updated_at timestamptz not null default now()  -- for "what changed since"
);

create table public.entries (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  session_id uuid not null,
  amount_ml int not null check (amount_ml > 0),
  logged_at timestamptz not null,
  updated_at timestamptz not null,
  deleted boolean not null default false,
  server_updated_at timestamptz not null default now()
);

create table public.settings (
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  key text not null,
  value text not null,
  updated_at timestamptz not null,
  server_updated_at timestamptz not null default now(),
  primary key (user_id, key)
);

create index on public.day_sessions (user_id, server_updated_at);
create index on public.entries (user_id, server_updated_at);
create index on public.settings (user_id, server_updated_at);

-- Only the signed-in user can read or write their own rows.
alter table public.day_sessions enable row level security;
alter table public.entries enable row level security;
alter table public.settings enable row level security;

create policy "own rows" on public.day_sessions for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "own rows" on public.entries for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "own rows" on public.settings for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- Last write wins: an update older than the stored row is ignored, and every
-- accepted write gets a fresh server timestamp so devices can pull just changes.
create or replace function public.lww_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and new.updated_at < old.updated_at then
    return null;
  end if;
  new.server_updated_at := clock_timestamp();
  return new;
end $$;

create trigger lww before insert or update on public.day_sessions
  for each row execute function public.lww_guard();
create trigger lww before insert or update on public.entries
  for each row execute function public.lww_guard();
create trigger lww before insert or update on public.settings
  for each row execute function public.lww_guard();

-- In-app "Delete account" (required by Google Play for apps with sign-up).
-- Deletes the caller's auth user; their rows go with it (on delete cascade).
create or replace function public.delete_my_account() returns void
language sql security definer set search_path = '' as $$
  delete from auth.users where id = (select auth.uid());
$$;
revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- Live updates to the other device while both apps are open.
alter publication supabase_realtime add table public.day_sessions, public.entries, public.settings;
