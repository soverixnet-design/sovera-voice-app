create table public.sovera_referral_codes (
 user_id uuid primary key references public.sovera_profiles(id) on delete cascade,
 code text not null unique default ('SV' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,12))),
 created_at timestamptz not null default now(),
 constraint sovera_referral_code_format check (code ~ '^SV[A-F0-9]{12}$')
);
create table public.sovera_referrals (
 referred_id uuid primary key default auth.uid() references public.sovera_profiles(id) on delete cascade,
 referral_code text not null references public.sovera_referral_codes(code) on delete cascade,
 created_at timestamptz not null default now()
);
create index sovera_referrals_code_date_idx on public.sovera_referrals(referral_code,created_at desc);
alter table public.sovera_referral_codes enable row level security;
alter table public.sovera_referrals enable row level security;
revoke all on public.sovera_referral_codes,public.sovera_referrals from public,anon,authenticated;
grant select on public.sovera_referral_codes,public.sovera_referrals to authenticated;
grant insert(user_id) on public.sovera_referral_codes to authenticated;
grant insert(referral_code) on public.sovera_referrals to authenticated;
grant all on public.sovera_referral_codes,public.sovera_referrals to service_role;
create policy sovera_referral_codes_own_read on public.sovera_referral_codes for select to authenticated using (user_id=(select auth.uid()));
create policy sovera_referral_codes_own_create on public.sovera_referral_codes for insert to authenticated with check (user_id=(select auth.uid()) and coalesce((select auth.jwt()->>'is_anonymous'),'false')<>'true');
create policy sovera_referrals_participant_read on public.sovera_referrals for select to authenticated using (
 referred_id=(select auth.uid()) or referral_code in (select code from public.sovera_referral_codes where user_id=(select auth.uid()))
);
create policy sovera_referrals_claim_once on public.sovera_referrals for insert to authenticated with check (
 referred_id=(select auth.uid()) and coalesce((select auth.jwt()->>'is_anonymous'),'false')<>'true' and
 not exists(select 1 from public.sovera_referral_codes c where c.user_id=(select auth.uid()) and c.code=sovera_referrals.referral_code)
);
comment on table public.sovera_referrals is 'One immutable referral claim per authenticated profile. No coins or wallet rewards are granted.';

