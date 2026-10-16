
create table public.sovera_rooms (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null unique references auth.users(id) on delete cascade,
 name text not null check(char_length(btrim(name)) between 1 and 40),
 category text not null default 'Adda' check(category in ('Adda','Music','Friends')),
 seat_count int not null default 9 check(seat_count in(5,6,9,12)),
 created_at timestamptz not null default now()
);
create index sovera_rooms_created_idx on public.sovera_rooms(created_at desc);
alter table public.sovera_rooms enable row level security;
revoke all on public.sovera_rooms from anon,authenticated;
grant select on public.sovera_rooms to authenticated;
grant insert(owner_id,name,category) on public.sovera_rooms to authenticated;
grant update(name,category,seat_count) on public.sovera_rooms to authenticated;
create policy rooms_read on public.sovera_rooms for select to authenticated using(true);
create policy rooms_create on public.sovera_rooms for insert to authenticated with check((select auth.uid())=owner_id);
create policy rooms_edit on public.sovera_rooms for update to authenticated using((select auth.uid())=owner_id) with check((select auth.uid())=owner_id);
create table public.sovera_room_follows (
 user_id uuid not null references auth.users(id) on delete cascade,
 room_id uuid not null references public.sovera_rooms(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key(user_id,room_id)
);
create index sovera_room_follows_room_idx on public.sovera_room_follows(room_id);
alter table public.sovera_room_follows enable row level security;
revoke all on public.sovera_room_follows from anon,authenticated;
grant select,delete on public.sovera_room_follows to authenticated;
grant insert(user_id,room_id) on public.sovera_room_follows to authenticated;
create policy follows_read on public.sovera_room_follows for select to authenticated using((select auth.uid())=user_id);
create policy follows_create on public.sovera_room_follows for insert to authenticated with check((select auth.uid())=user_id);
create policy follows_delete on public.sovera_room_follows for delete to authenticated using((select auth.uid())=user_id);
create table public.sovera_support_tickets(
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 topic text not null check(topic in('Official support','Recharge support')),
 message text not null check(char_length(btrim(message)) between 1 and 1000),
 status text not null default 'open' check(status in('open','closed')),
 created_at timestamptz not null default now()
);
create index sovera_support_user_idx on public.sovera_support_tickets(user_id,created_at desc);
alter table public.sovera_support_tickets enable row level security;
revoke all on public.sovera_support_tickets from anon,authenticated;
grant select on public.sovera_support_tickets to authenticated;
grant insert(user_id,topic,message) on public.sovera_support_tickets to authenticated;
create policy support_read on public.sovera_support_tickets for select to authenticated using((select auth.uid())=user_id);
create policy support_create on public.sovera_support_tickets for insert to authenticated with check((select auth.uid())=user_id);

