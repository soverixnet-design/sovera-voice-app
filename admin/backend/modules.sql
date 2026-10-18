-- Additive admin modules. Existing accounting entries are never rewritten.
create table public.sovera_system_settings(
 id boolean primary key default true check(id),exchange_enabled boolean not null default false,
 exchange_diamonds bigint not null default 100 check(exchange_diamonds between 1 and 1000000),exchange_coins bigint not null default 70 check(exchange_coins between 1 and 1000000),
 daily_enabled boolean not null default false,daily_coins bigint not null default 0 check(daily_coins between 0 and 100000),daily_frame uuid references public.sovera_admin_content(id),daily_frame_hours integer not null default 24 check(daily_frame_hours between 1 and 8760),updated_at timestamptz not null default now()
);
insert into public.sovera_system_settings(id) values(true);
create table public.sovera_inventory_grants(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.sovera_profiles(id),item_id uuid not null references public.sovera_admin_content(id),source text not null check(source in('staff','daily')),actor_id uuid references public.sovera_profiles(id),expires_at timestamptz not null,revoked boolean not null default false,created_at timestamptz not null default now());
create index sovera_inventory_user on public.sovera_inventory_grants(user_id,expires_at);
create table public.sovera_daily_claims(user_id uuid not null references public.sovera_profiles(id),day date not null,coins bigint not null,frame_id uuid references public.sovera_admin_content(id),created_at timestamptz not null default now(),primary key(user_id,day));
create table public.sovera_moments(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.sovera_profiles(id),body text not null check(char_length(btrim(body)) between 1 and 2000),hidden boolean not null default false,deleted boolean not null default false,created_at timestamptz not null default now());
create index sovera_moments_time on public.sovera_moments(created_at desc);
create table public.sovera_reports(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.sovera_profiles(id),kind text not null check(kind in('room','user','moment')),target_id uuid not null,reason text not null check(char_length(btrim(reason)) between 5 and 1000),status text not null default 'open' check(status in('open','resolved','dismissed')),admin_note text not null default '' check(char_length(admin_note)<=2000),created_at timestamptz not null default now());
create index sovera_reports_status on public.sovera_reports(status,created_at desc);
create index sovera_reports_user on public.sovera_reports(user_id);
create table public.sovera_room_presence(room_id uuid not null references public.sovera_rooms(id) on delete cascade,user_id uuid primary key references public.sovera_profiles(id),seen_at timestamptz not null default now());
create index sovera_presence_room on public.sovera_room_presence(room_id,seen_at);
create table public.sovera_connections(id uuid primary key default gen_random_uuid(),sender_id uuid not null references public.sovera_profiles(id),receiver_id uuid not null references public.sovera_profiles(id),kind text not null check(kind in('friend','cp')),status text not null default 'pending' check(status in('pending','accepted','declined','ended')),created_at timestamptz not null default now(),check(sender_id<>receiver_id));
create unique index sovera_connection_pair on public.sovera_connections(least(sender_id,receiver_id),greatest(sender_id,receiver_id),kind) where status in('pending','accepted');
create index sovera_connections_receiver on public.sovera_connections(receiver_id,status);
create index sovera_connections_sender on public.sovera_connections(sender_id,status);
alter table public.sovera_profiles add column location text not null default '' check(char_length(location)<=100),add column onboarded boolean not null default false,add column active_frame uuid references public.sovera_admin_content(id);
grant update(location,onboarded) on public.sovera_profiles to authenticated;
alter table public.sovera_admin_content drop constraint sovera_admin_content_kind_check;
alter table public.sovera_admin_content add constraint sovera_admin_content_kind_check check(kind in('banner','notice','gift','frame','entry','medal','tag','event','vip','effect','notification','update'));
do $$ declare t text;begin foreach t in array array['sovera_system_settings','sovera_inventory_grants','sovera_daily_claims','sovera_moments','sovera_reports','sovera_room_presence','sovera_connections'] loop
 execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from anon,authenticated',t);execute format('grant all on public.%I to service_role',t);
 execute format('create policy sovera_ban_guard on public.%I as restrictive for all to authenticated using(not (select sovera_private.is_blocked())) with check(not (select sovera_private.is_blocked()))',t);
 end loop;end $$;
grant select on public.sovera_system_settings to authenticated;
create policy settings_read on public.sovera_system_settings for select to authenticated using(true);
grant select on public.sovera_inventory_grants,public.sovera_daily_claims to authenticated;
create policy inventory_read on public.sovera_inventory_grants for select to authenticated using(user_id=(select auth.uid()));
create policy daily_read on public.sovera_daily_claims for select to authenticated using(user_id=(select auth.uid()));
-- App operations enforce the signed-in actor inside an unexposed private function.
create function sovera_private.app_action(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();cfg public.sovera_system_settings;day_key date:=(now() at time zone 'UTC')::date;item public.sovera_admin_content;target uuid;connection public.sovera_connections;entry public.sovera_wallet_entries;request uuid;amount bigint;coin_amount bigint;balance bigint;result jsonb;
begin
 if actor is null or not exists(select 1 from public.sovera_profiles where id=actor and not is_banned) then raise exception 'Sign in with an active account';end if;
 if p_action='daily.claim' then
  perform 1 from public.sovera_profiles where id=actor for update;
  select * into cfg from public.sovera_system_settings where id;
  if not cfg.daily_enabled then return jsonb_build_object('enabled',false);end if;
  if exists(select 1 from public.sovera_daily_claims where user_id=actor and day=day_key) then return jsonb_build_object('enabled',true,'already_claimed',true);end if;
  insert into public.sovera_wallets(user_id) values(actor) on conflict do nothing;
  perform 1 from public.sovera_wallets where user_id=actor and status='active' for update;if not found then raise exception 'Wallet frozen';end if;
  insert into public.sovera_daily_claims(user_id,day,coins,frame_id) values(actor,day_key,cfg.daily_coins,cfg.daily_frame);
  if cfg.daily_coins>0 then insert into public.sovera_wallet_entries(user_id,coin_delta,kind,reference) values(actor,cfg.daily_coins,'adjustment','daily:'||actor||':'||day_key);end if;
  if cfg.daily_frame is not null then
   select * into item from public.sovera_admin_content where id=cfg.daily_frame and kind='frame' and published;
   if found then insert into public.sovera_inventory_grants(user_id,item_id,source,expires_at) values(actor,item.id,'daily',now()+make_interval(hours=>cfg.daily_frame_hours));end if;
  end if;
  return jsonb_build_object('enabled',true,'coins',cfg.daily_coins::text,'frame_id',item.id,'day',day_key);
 elsif p_action='exchange' then
  amount:=(p_data->>'diamonds')::bigint;request:=(p_data->>'request_id')::uuid;
  if amount is null or amount<1 or amount>1000000000 or request is null then raise exception 'Invalid exchange';end if;
  perform 1 from public.sovera_profiles where id=actor for update;
  select * into entry from public.sovera_wallet_entries where reference='exchange:'||actor||':'||request;
  if found then if entry.diamond_delta<>-amount then raise exception 'Request ID used with another amount';end if;return jsonb_build_object('coins',entry.coin_delta::text,'duplicate',true);end if;
  select * into cfg from public.sovera_system_settings where id;
  if not cfg.exchange_enabled then raise exception 'Diamond exchange is disabled';end if;
  if amount%cfg.exchange_diamonds<>0 then raise exception 'Use a multiple of % Diamonds',cfg.exchange_diamonds;end if;
  coin_amount:=(amount/cfg.exchange_diamonds)*cfg.exchange_coins;
  perform 1 from public.sovera_wallets where user_id=actor and status='active' for update;if not found then raise exception 'Wallet unavailable';end if;
  select coalesce(sum(diamond_delta),0) into balance from public.sovera_wallet_entries where user_id=actor;
  if balance<amount then raise exception 'Insufficient Diamonds';end if;
  insert into public.sovera_wallet_entries(user_id,coin_delta,diamond_delta,kind,reference) values(actor,coin_amount,-amount,'exchange','exchange:'||actor||':'||request);
  return jsonb_build_object('coins',coin_amount::text,'diamonds',amount::text);
 elsif p_action='inventory' then
  return(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select g.id,g.item_id,g.expires_at,c.title,c.kind,c.payload from public.sovera_inventory_grants g join public.sovera_admin_content c on c.id=g.item_id where g.user_id=actor and not g.revoked and g.expires_at>now() order by g.created_at desc)x);
 elsif p_action='frame.lookup' then
  return(select jsonb_build_object('title',c.title,'asset_url',c.payload->>'asset_url') from public.sovera_profiles p join public.sovera_admin_content c on c.id=p.active_frame where p.uid=(p_data->>'uid')::bigint and not p.is_banned and c.kind='frame' and c.published and exists(select 1 from public.sovera_inventory_grants g where g.user_id=p.id and g.item_id=c.id and not g.revoked and g.expires_at>now()));
 elsif p_action='frame.equip' then
  target:=nullif(p_data->>'item_id','')::uuid;
  if target is not null and not exists(select 1 from public.sovera_inventory_grants g join public.sovera_admin_content c on c.id=g.item_id where g.user_id=actor and g.item_id=target and not g.revoked and g.expires_at>now() and c.kind='frame') then raise exception 'Frame is not owned or expired';end if;
  update public.sovera_profiles set active_frame=target where id=actor;return jsonb_build_object('saved',true);
 elsif p_action='moments' then
  return(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select m.id,m.user_id,m.body,m.created_at,p.uid,p.display_name,p.avatar_url,p.country from public.sovera_moments m join public.sovera_profiles p on p.id=m.user_id where not m.hidden and not m.deleted and not p.is_banned order by m.created_at desc limit 50)x);
 elsif p_action='moment.create' then
  if (select count(*) from public.sovera_moments where user_id=actor and created_at>now()-interval '1 minute')>=3 then raise exception 'Please wait before posting again';end if;
  insert into public.sovera_moments(user_id,body) values(actor,p_data->>'body') returning id into target;return jsonb_build_object('id',target);
 elsif p_action='moment.delete' then
  update public.sovera_moments set deleted=true where id=(p_data->>'id')::uuid and user_id=actor;return jsonb_build_object('saved',found);
 elsif p_action='report.create' then
  if (select count(*) from public.sovera_reports where user_id=actor and created_at>now()-interval '1 hour')>=20 then raise exception 'Report limit reached';end if;
  target:=(p_data->>'target')::uuid;
  if not(case p_data->>'kind' when 'user' then exists(select 1 from public.sovera_profiles where id=target) when 'room' then exists(select 1 from public.sovera_rooms where id=target) when 'moment' then exists(select 1 from public.sovera_moments where id=target) else false end) then raise exception 'Report target not found';end if;
  insert into public.sovera_reports(user_id,kind,target_id,reason) values(actor,p_data->>'kind',target,p_data->>'reason');return jsonb_build_object('saved',true);
 elsif p_action='presence.ping' then
  target:=(p_data->>'room_id')::uuid;
  if not exists(select 1 from public.sovera_rooms where id=target and not is_closed) then raise exception 'Room closed';end if;
  insert into public.sovera_room_presence(room_id,user_id,seen_at) values(target,actor,now()) on conflict(user_id) do update set room_id=excluded.room_id,seen_at=now();return jsonb_build_object('saved',true);
 elsif p_action='presence.leave' then
  delete from public.sovera_room_presence where user_id=actor and room_id=(p_data->>'room_id')::uuid;return jsonb_build_object('saved',true);
 elsif p_action='presence.counts' then
  return(select coalesce(jsonb_object_agg(room_id,n),'{}') from(select room_id,count(*) as n from public.sovera_room_presence where seen_at>now()-interval '90 seconds' group by room_id)x);
 elsif p_action='connections' then
  return(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select c.*,p.uid,p.display_name,p.avatar_url from public.sovera_connections c join public.sovera_profiles p on p.id=case when c.sender_id=actor then c.receiver_id else c.sender_id end where actor in(c.sender_id,c.receiver_id) and c.status in('pending','accepted') order by c.created_at desc limit 100)x);
 elsif p_action='connection.request' then
  select id into target from public.sovera_profiles where uid=(p_data->>'uid')::bigint and not is_banned;
  if target is null or target=actor then raise exception 'Choose another active user';end if;
  perform 1 from public.sovera_profiles where id in(actor,target) order by id for update;
  if p_data->>'kind'='cp' and exists(select 1 from public.sovera_connections where kind='cp' and status='accepted' and (sender_id in(actor,target) or receiver_id in(actor,target))) then raise exception 'One account already has a CP partner';end if;
  insert into public.sovera_connections(sender_id,receiver_id,kind) values(actor,target,p_data->>'kind');return jsonb_build_object('saved',true);
 elsif p_action='connection.respond' then
  select * into connection from public.sovera_connections where id=(p_data->>'id')::uuid;
  if not found or actor not in(connection.sender_id,connection.receiver_id) then raise exception 'Connection unavailable';end if;
  perform 1 from public.sovera_profiles where id in(connection.sender_id,connection.receiver_id) order by id for update;
  select * into connection from public.sovera_connections where id=connection.id for update;
  if p_data->>'response'='accept' then
   if actor<>connection.receiver_id or connection.status<>'pending' then raise exception 'Only the invited user can accept';end if;
   if connection.kind='cp' and exists(select 1 from public.sovera_connections where kind='cp' and status='accepted' and (sender_id in(connection.sender_id,connection.receiver_id) or receiver_id in(connection.sender_id,connection.receiver_id))) then raise exception 'One account already has a CP partner';end if;
   update public.sovera_connections set status='accepted' where id=connection.id;
  elsif p_data->>'response'='end' then update public.sovera_connections set status=case when status='pending' then 'declined' else 'ended' end where id=connection.id;
  else raise exception 'Invalid response';end if;return jsonb_build_object('saved',true);
 end if;raise exception 'Unknown app action';
end $$;
revoke all on function sovera_private.app_action(text,jsonb) from public,anon;
grant execute on function sovera_private.app_action(text,jsonb) to authenticated;
create function public.sovera_app_action(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select sovera_private.app_action(p_action,p_data)$$;
revoke all on function public.sovera_app_action(text,jsonb) from public,anon;
grant execute on function public.sovera_app_action(text,jsonb) to authenticated;
-- Keep base admin controls; extend through the same authenticated gateway.
alter function public.sovera_admin_run(uuid,text,jsonb) rename to sovera_admin_core;
revoke all on function public.sovera_admin_core(uuid,text,jsonb) from public,anon,authenticated;
create function public.sovera_admin_run(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security invoker set search_path='' as $$
declare staff public.sovera_admin_staff;needed text;target public.sovera_profiles;item public.sovera_admin_content;g public.sovera_inventory_grants;perms text[];old_perms text[];hours integer;request uuid;result jsonb;cfg public.sovera_system_settings;
begin
 select * into staff from public.sovera_admin_staff where user_id=p_actor and active for update;
 if not found or exists(select 1 from public.sovera_profiles where id=p_actor and is_banned) then raise exception 'Admin access revoked';end if;
 if p_action='staff.save' then
  if staff.role<>'owner' then raise exception 'Only the owner manages staff';end if;
  select coalesce(array_agg(v),'{}') into perms from jsonb_array_elements_text(coalesce(p_data->'permissions','[]'))v;
  if not perms<@array['dashboard.read','users.read','users.moderate','vip.manage','recharge.create','history.read','audit.read','rooms.manage','content.manage','events.manage','support.manage','finance.read','inventory.grant','moderation.manage','analytics.read','settings.read']::text[] then raise exception 'Invalid permissions';end if;
  if 'recharge.create'=any(perms) and not 'users.read'=any(perms) then raise exception 'Recharge requires user lookup permission';end if;
  select coalesce(array_agg(v),'{}') into old_perms from unnest(perms)v where v<>all(array['finance.read','inventory.grant','moderation.manage','analytics.read','settings.read']);
  result:=public.sovera_admin_core(p_actor,p_action,jsonb_set(p_data,'{permissions}',to_jsonb(old_perms)));
  update public.sovera_admin_staff set permissions=perms where user_id=(p_data->>'target')::uuid;
  insert into public.sovera_admin_audit(actor_id,action,target_id,details) values(p_actor,'staff.permissions',(p_data->>'target')::uuid,jsonb_build_object('permissions',perms));return result;
 end if;
 needed:=case p_action when 'finance' then 'finance.read' when 'sellers' then 'owner' when 'seller.save' then 'owner' when 'settings' then 'settings.read' when 'settings.save' then 'owner' when 'inventory' then 'inventory.grant' when 'inventory.grant' then 'inventory.grant' when 'inventory.revoke' then 'inventory.grant' when 'moderation' then 'moderation.manage' when 'report.resolve' then 'moderation.manage' when 'moment.moderate' then 'moderation.manage' when 'analytics' then 'analytics.read' when 'room.monitor' then 'rooms.manage' else null end;
 if needed is null then return public.sovera_admin_core(p_actor,p_action,p_data);end if;
 if staff.role<>'owner' and (needed='owner' or not needed=any(staff.permissions)) then raise exception 'Permission denied: %',needed;end if;
 if p_action='finance' then
  return(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select e.id,p.uid,p.display_name,e.coin_delta::text,e.diamond_delta::text,e.kind,e.reference,e.created_at from public.sovera_wallet_entries e join public.sovera_profiles p on p.id=e.user_id where(coalesce(p_data->>'uid','')='' or p.uid::text=p_data->>'uid') and(coalesce(p_data->>'kind','')='' or e.kind=p_data->>'kind') order by e.created_at desc,e.id desc limit 100 offset least(greatest(coalesce((p_data->>'offset')::int,0),0),100000))x);
 elsif p_action='sellers' then
  return jsonb_build_object('sellers',(select coalesce(jsonb_agg(to_jsonb(s)),'[]') from public.sovera_coin_sellers s),'applications',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select a.*,p.uid,p.display_name from public.sovera_reseller_applications a join public.sovera_profiles p on p.id=a.user_id order by a.created_at desc limit 100)x));
 elsif p_action='seller.save' then
  select * into target from public.sovera_profiles where uid=(p_data->>'uid')::bigint and not is_banned for update;if not found then raise exception 'Active user not found';end if;
  insert into public.sovera_coin_sellers(seller_uid,display_name,country,languages,description,published) values(target.uid,target.display_name,p_data->>'country',coalesce(p_data->>'languages',''),coalesce(p_data->>'description',''),coalesce((p_data->>'published')::boolean,false)) on conflict(seller_uid) do update set display_name=excluded.display_name,country=excluded.country,languages=excluded.languages,description=excluded.description,published=excluded.published,updated_at=now();
  update public.sovera_reseller_applications set status='approved' where user_id=target.id and coalesce((p_data->>'published')::boolean,false);
 elsif p_action='settings' then return (select to_jsonb(s) from public.sovera_system_settings s where id);
 elsif p_action='settings.save' then
  if nullif(p_data->>'daily_frame','') is not null and not exists(select 1 from public.sovera_admin_content where id=(p_data->>'daily_frame')::uuid and kind='frame' and published) then raise exception 'Choose a published frame';end if;
  update public.sovera_system_settings set exchange_enabled=(p_data->>'exchange_enabled')::boolean,exchange_diamonds=(p_data->>'exchange_diamonds')::bigint,exchange_coins=(p_data->>'exchange_coins')::bigint,daily_enabled=(p_data->>'daily_enabled')::boolean,daily_coins=(p_data->>'daily_coins')::bigint,daily_frame=nullif(p_data->>'daily_frame','')::uuid,daily_frame_hours=(p_data->>'daily_frame_hours')::int,updated_at=now() where id;
 elsif p_action='inventory' then
  return jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(c)),'[]') from public.sovera_admin_content c where c.kind in('frame','entry','effect','vip','medal','tag') and c.published),'grants',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select g.*,p.uid,c.title from public.sovera_inventory_grants g join public.sovera_profiles p on p.id=g.user_id join public.sovera_admin_content c on c.id=g.item_id order by g.created_at desc limit 100)x));
 elsif p_action='inventory.grant' then
  hours:=(p_data->>'hours')::int;request:=(p_data->>'request_id')::uuid;if hours is null or hours<1 or hours>8760 or request is null then raise exception 'Choose a duration between 1 and 8760 hours';end if;
  select * into target from public.sovera_profiles where uid=(p_data->>'uid')::bigint and not is_banned;if not found then raise exception 'Active recipient not found';end if;
  select * into item from public.sovera_admin_content where id=(p_data->>'item_id')::uuid and published and kind in('frame','entry','effect','vip','medal','tag');if not found then raise exception 'Published store item not found';end if;
  perform pg_advisory_xact_lock(hashtextextended(request::text,418));
  select * into g from public.sovera_inventory_grants where id=request;
  if found then if g.user_id<>target.id or g.item_id<>item.id or g.actor_id<>p_actor then raise exception 'Grant request ID already used';end if;return jsonb_build_object('saved',true,'duplicate',true);end if;
  insert into public.sovera_inventory_grants(id,user_id,item_id,source,actor_id,expires_at) values(request,target.id,item.id,'staff',p_actor,now()+make_interval(hours=>hours));
 elsif p_action='inventory.revoke' then
  select * into g from public.sovera_inventory_grants where id=(p_data->>'id')::uuid for update;if not found then raise exception 'Grant not found';end if;
  if staff.role<>'owner' and g.actor_id is distinct from p_actor then raise exception 'Only the owner can revoke another issuer grant';end if;
  update public.sovera_inventory_grants set revoked=true where id=g.id;
 elsif p_action='moderation' then
  return jsonb_build_object('reports',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select r.*,p.uid,p.display_name from public.sovera_reports r join public.sovera_profiles p on p.id=r.user_id order by r.created_at desc limit 100)x),'moments',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select m.*,p.uid,p.display_name from public.sovera_moments m join public.sovera_profiles p on p.id=m.user_id order by m.created_at desc limit 100)x));
 elsif p_action='report.resolve' then
  update public.sovera_reports set status=p_data->>'status',admin_note=coalesce(p_data->>'note','') where id=(p_data->>'id')::uuid;if not found then raise exception 'Report not found';end if;
 elsif p_action='moment.moderate' then
  update public.sovera_moments set hidden=(p_data->>'hidden')::boolean where id=(p_data->>'id')::uuid and not deleted;if not found then raise exception 'Post unavailable';end if;
 elsif p_action='room.monitor' then
  return(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select r.id,r.name,r.is_closed,r.owner_id,(select count(*) from public.sovera_room_presence pr where pr.room_id=r.id and pr.seen_at>now()-interval '90 seconds') as occupants,(select coalesce(jsonb_agg(jsonb_build_object('uid',p.uid,'display_name',p.display_name,'seen_at',pr.seen_at)),'[]') from public.sovera_room_presence pr join public.sovera_profiles p on p.id=pr.user_id where pr.room_id=r.id and pr.seen_at>now()-interval '90 seconds') as participants from public.sovera_rooms r where staff.role<>'room_admin' or r.id=any(staff.room_ids) order by r.created_at desc limit 100)x);
 elsif p_action='analytics' then
  return jsonb_build_object('users',(select count(*) from public.sovera_profiles),'new_users_7d',(select count(*) from public.sovera_profiles where created_at>=now()-interval '7 days'),'active_room_users',(select count(*) from public.sovera_room_presence where seen_at>now()-interval '90 seconds'),'daily_claims_today',(select count(*) from public.sovera_daily_claims where day=(now() at time zone 'UTC')::date),'open_reports',(select count(*) from public.sovera_reports where status='open'),'posts',(select count(*) from public.sovera_moments where not hidden and not deleted),'coins_issued',(select coalesce(sum(coin_delta) filter(where coin_delta>0),0)::text from public.sovera_wallet_entries),'diamonds_exchanged',(select coalesce(-sum(diamond_delta),0)::text from public.sovera_wallet_entries where kind='exchange'),'cash_revenue',null,'crash_rate',null,'voice_latency',null);
 end if;
 insert into public.sovera_admin_audit(actor_id,action,target_id,details) values(p_actor,p_action,target.id,p_data);return jsonb_build_object('saved',true);
end $$;
revoke all on function public.sovera_admin_run(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.sovera_admin_run(uuid,text,jsonb) to service_role;
grant select,insert,update on public.sovera_coin_sellers,public.sovera_reseller_applications to service_role;
notify pgrst,'reload schema';
-- Public profile photos contain no private documents. Only the user owns upload paths.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('sovera-profile-photos','sovera-profile-photos',true,2097152,array['image/png']) on conflict(id) do nothing;
create policy sovera_profile_photo_insert on storage.objects for insert to authenticated with check(bucket_id='sovera-profile-photos' and (storage.foldername(name))[1]=(select auth.uid())::text and not (select sovera_private.is_blocked()));
create policy sovera_profile_photo_update on storage.objects for update to authenticated using(bucket_id='sovera-profile-photos' and (storage.foldername(name))[1]=(select auth.uid())::text and not (select sovera_private.is_blocked())) with check(bucket_id='sovera-profile-photos' and (storage.foldername(name))[1]=(select auth.uid())::text and not (select sovera_private.is_blocked()));
create policy sovera_profile_photo_select on storage.objects for select to authenticated using(bucket_id='sovera-profile-photos' and (storage.foldername(name))[1]=(select auth.uid())::text);

-- Keep directory names, public photos and country flags consistent with profile edits.
alter table public.sovera_member_cards add column country text not null default '';
grant insert(country),update(country) on public.sovera_member_cards to authenticated;
update public.sovera_member_cards m set country=p.country from public.sovera_profiles p where p.id=m.user_id;
create function public.sovera_sync_public_profile() returns trigger language plpgsql security invoker set search_path='' as $$begin update public.sovera_member_cards set display_name=new.display_name,avatar_url=new.avatar_url,bio=new.bio,country=new.country where user_id=new.id;return new;end$$;
revoke all on function public.sovera_sync_public_profile() from public,anon,authenticated;
create trigger sovera_profile_public_sync after update of display_name,avatar_url,bio,country on public.sovera_profiles for each row execute function public.sovera_sync_public_profile();
create function public.sovera_member_country() returns trigger language plpgsql security invoker set search_path='' as $$begin select country into new.country from public.sovera_profiles where id=new.user_id;return new;end$$;
revoke all on function public.sovera_member_country() from public,anon,authenticated;
create trigger sovera_member_country before insert on public.sovera_member_cards for each row execute function public.sovera_member_country();
