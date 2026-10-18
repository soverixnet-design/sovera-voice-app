-- Public-facing member cards are opt-in; private sovera_profiles stays private.
create table public.sovera_member_cards (
 user_id uuid primary key references auth.users(id) on delete cascade,
 uid bigint not null unique references public.sovera_profiles(uid) on delete cascade,
 display_name text not null check(char_length(btrim(display_name)) between 1 and 40),
 listed boolean not null default false
);
create table public.sovera_user_follows (
 follower_id uuid not null references auth.users(id) on delete cascade,
 following_id uuid not null references public.sovera_member_cards(user_id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key(follower_id,following_id),check(follower_id<>following_id)
);
create index sovera_user_follows_target_idx on public.sovera_user_follows(following_id);
alter table public.sovera_member_cards enable row level security;
alter table public.sovera_user_follows enable row level security;
revoke all on public.sovera_member_cards,public.sovera_user_follows from anon,authenticated;
grant select,insert,update,delete on public.sovera_member_cards to authenticated;
grant select,insert,delete on public.sovera_user_follows to authenticated;
grant all on public.sovera_member_cards,public.sovera_user_follows to service_role;
create policy sovera_member_read on public.sovera_member_cards for select to authenticated using(listed or user_id=(select auth.uid()));
create policy sovera_member_publish on public.sovera_member_cards for insert to authenticated with check(user_id=(select auth.uid()) and uid=(select uid from public.sovera_profiles where id=(select auth.uid())));
create policy sovera_member_edit on public.sovera_member_cards for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()) and uid=(select uid from public.sovera_profiles where id=(select auth.uid())));
create policy sovera_member_remove on public.sovera_member_cards for delete to authenticated using(user_id=(select auth.uid()));
create policy sovera_follows_read on public.sovera_user_follows for select to authenticated using(follower_id=(select auth.uid()));
create policy sovera_follows_add on public.sovera_user_follows for insert to authenticated with check(follower_id=(select auth.uid()) and follower_id<>following_id and exists(select 1 from public.sovera_member_cards where user_id=following_id and listed));
create policy sovera_follows_remove on public.sovera_user_follows for delete to authenticated using(follower_id=(select auth.uid()));
