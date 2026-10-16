begin;
insert into auth.users(id) values ('bbccddaa-0000-4000-8000-000000000001'),('bbccddaa-0000-4000-8000-000000000002'),('bbccddaa-0000-4000-8000-000000000003');
insert into public.sovera_profiles(id,display_name) values ('bbccddaa-0000-4000-8000-000000000001','Test one'),('bbccddaa-0000-4000-8000-000000000002','Test two'),('bbccddaa-0000-4000-8000-000000000003','Hidden test');
insert into public.sovera_member_cards(user_id,uid,display_name,listed) select id,uid,display_name,id<>'bbccddaa-0000-4000-8000-000000000003' from public.sovera_profiles where id in ('bbccddaa-0000-4000-8000-000000000001','bbccddaa-0000-4000-8000-000000000002','bbccddaa-0000-4000-8000-000000000003');
set local role authenticated;
select set_config('request.jwt.claim.sub','bbccddaa-0000-4000-8000-000000000001',true);
do $$ begin
 if(select count(*) from public.sovera_member_cards)<>2 then raise exception 'hidden card exposed';end if;
 insert into public.sovera_user_follows(follower_id,following_id) values ('bbccddaa-0000-4000-8000-000000000001','bbccddaa-0000-4000-8000-000000000002');
 if(select count(*) from public.sovera_user_follows)<>1 then raise exception 'follow missing';end if;
 begin
 insert into public.sovera_user_follows(follower_id,following_id) values ('bbccddaa-0000-4000-8000-000000000001','bbccddaa-0000-4000-8000-000000000003');raise exception 'hidden target accepted';
 exception when insufficient_privilege then null;end;
 begin
 insert into public.sovera_user_follows(follower_id,following_id) values ('bbccddaa-0000-4000-8000-000000000002','bbccddaa-0000-4000-8000-000000000001');raise exception 'forged follower accepted';
 exception when insufficient_privilege then null;end;
 delete from public.sovera_user_follows where following_id='bbccddaa-0000-4000-8000-000000000002';
 if(select count(*) from public.sovera_user_follows)<>0 then raise exception 'unfollow failed';end if;
end $$;
reset role;
rollback;
