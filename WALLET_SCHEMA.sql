-- Read-only wallet ledger and owner-published seller directory.
-- Only trusted backend operators may write; no client balance/approval paths.
create table public.sovera_wallets (
 user_id uuid primary key references auth.users(id) on delete cascade,
 status text not null default 'active' check (status in ('active','frozen')),
 created_at timestamptz not null default now()
);
create table public.sovera_wallet_entries (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.sovera_wallets(user_id) on delete cascade,
 coin_delta bigint not null default 0,
 diamond_delta bigint not null default 0,
 kind text not null check (kind in ('recharge','gift','exchange','adjustment')),
 reference text not null unique check (char_length(reference) between 1 and 100),
 created_at timestamptz not null default now(),
 check (coin_delta <> 0 or diamond_delta <> 0)
);
create index sovera_wallet_entries_user_time on public.sovera_wallet_entries(user_id,created_at desc,id desc);
create table public.sovera_coin_sellers (
 seller_uid bigint primary key references public.sovera_profiles(uid) on delete cascade,
 display_name text not null check (char_length(btrim(display_name)) between 1 and 40),
 country text not null check (char_length(btrim(country)) between 1 and 80),
 languages text not null default '' check (char_length(languages) <= 120),
 description text not null default '' check (char_length(description) <= 300),
 published boolean not null default false,
 updated_at timestamptz not null default now()
);
alter table public.sovera_wallets enable row level security;
alter table public.sovera_wallet_entries enable row level security;
alter table public.sovera_coin_sellers enable row level security;
revoke all on public.sovera_wallets,public.sovera_wallet_entries,public.sovera_coin_sellers from anon,authenticated;
grant select on public.sovera_wallets,public.sovera_wallet_entries to authenticated;
grant select on public.sovera_coin_sellers to anon,authenticated;
grant all on public.sovera_wallets,public.sovera_wallet_entries,public.sovera_coin_sellers to service_role;
create policy sovera_wallet_owner_read on public.sovera_wallets for select to authenticated using ((select auth.uid())=user_id);
create policy sovera_ledger_owner_read on public.sovera_wallet_entries for select to authenticated using ((select auth.uid())=user_id);
create policy sovera_published_sellers_read on public.sovera_coin_sellers for select to anon,authenticated using (published);
create view public.sovera_wallet_balances with (security_invoker=true) as
 select w.user_id,w.status,coalesce(sum(e.coin_delta),0)::text as coins,coalesce(sum(e.diamond_delta),0)::text as diamonds
 from public.sovera_wallets w left join public.sovera_wallet_entries e on e.user_id=w.user_id
 group by w.user_id,w.status;
revoke all on public.sovera_wallet_balances from anon,authenticated;
grant select on public.sovera_wallet_balances to authenticated,service_role;
