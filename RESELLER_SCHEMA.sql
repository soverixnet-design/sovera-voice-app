
create table public.sovera_reseller_applications(
 user_id uuid primary key references auth.users(id) on delete cascade,
 note text not null check(char_length(btrim(note)) between 10 and 500),
 status text not null default 'pending' check(status in('pending','approved','declined')),
 created_at timestamptz not null default now()
);
alter table public.sovera_reseller_applications enable row level security;
revoke all on public.sovera_reseller_applications from anon,authenticated;
grant select on public.sovera_reseller_applications to authenticated;
grant insert(user_id,note) on public.sovera_reseller_applications to authenticated;
create policy reseller_application_read on public.sovera_reseller_applications for select to authenticated using((select auth.uid())=user_id);
create policy reseller_application_create on public.sovera_reseller_applications for insert to authenticated with check((select auth.uid())=user_id);
create table public.sovera_reseller_accounts(
 user_id uuid primary key references auth.users(id) on delete cascade,
 status text not null default 'suspended' check(status in('active','suspended')),
 tier text not null default 'Standard' check(char_length(tier) between 1 and 40),
 coin_quota bigint not null default 0 check(coin_quota>=0),
 used_quota bigint not null default 0 check(used_quota>=0 and used_quota<=coin_quota),
 updated_at timestamptz not null default now()
);
alter table public.sovera_reseller_accounts enable row level security;
revoke all on public.sovera_reseller_accounts from anon,authenticated;
grant select on public.sovera_reseller_accounts to authenticated;
create policy reseller_account_read on public.sovera_reseller_accounts for select to authenticated using((select auth.uid())=user_id);
create table public.sovera_profile_levels(
 user_id uuid primary key references auth.users(id) on delete cascade,
 wealth_level integer not null default 0 check(wealth_level between 0 and 999),
 charm_level integer not null default 0 check(charm_level between 0 and 999),
 vip_level integer not null default 0 check(vip_level between 0 and 999),
 updated_at timestamptz not null default now()
);
alter table public.sovera_profile_levels enable row level security;
revoke all on public.sovera_profile_levels from anon,authenticated;
grant select on public.sovera_profile_levels to authenticated;
create policy profile_levels_read on public.sovera_profile_levels for select to authenticated using((select auth.uid())=user_id);
