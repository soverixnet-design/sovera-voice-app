-- Pending explicit approval: do not run automatically in CI or installers.
-- Add room country storage; existing owner-only RLS remains in force.
begin;
alter table public.sovera_rooms add column if not exists country text not null default '' check (country = '' or country ~ '^[A-Z]{2}$');
update public.sovera_rooms r set country=p.country from public.sovera_profiles p where p.id=r.owner_id and p.country ~ '^[A-Z]{2}$' and r.country='';
grant update(country) on public.sovera_rooms to authenticated;
-- Profile photos are intended to be visible on members' public profiles.
-- Upload/replace is restricted to exactly the signed-in user's avatar path.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('sovera-profile-photos','sovera-profile-photos',true,2097152,array['image/png']) on conflict(id) do nothing;
create policy sovera_avatar_insert_self on storage.objects for insert to authenticated
with check(bucket_id='sovera-profile-photos' and name=(select auth.uid())::text||'/avatar.png');
create policy sovera_avatar_read_self on storage.objects for select to authenticated
using(bucket_id='sovera-profile-photos' and name=(select auth.uid())::text||'/avatar.png');
create policy sovera_avatar_update_self on storage.objects for update to authenticated
using(bucket_id='sovera-profile-photos' and name=(select auth.uid())::text||'/avatar.png')
with check(bucket_id='sovera-profile-photos' and name=(select auth.uid())::text||'/avatar.png');
commit;
