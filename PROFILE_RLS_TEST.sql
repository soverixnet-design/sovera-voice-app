begin;
insert into auth.users(id) values('bbccddaa-1111-4000-8000-000000000001'),('bbccddaa-1111-4000-8000-000000000002'),('bbccddaa-1111-4000-8000-000000000003');
-- Explicit fixture IDs leave the real registration sequence untouched.
insert into public.sovera_profiles(id,uid,display_name) overriding system value values('bbccddaa-1111-4000-8000-000000000001',910001,'Profile test one'),('bbccddaa-1111-4000-8000-000000000002',910002,'Profile test two'),('bbccddaa-1111-4000-8000-000000000003',910003,'Profile test outsider');
insert into public.sovera_member_cards(user_id,uid,display_name,listed) select id,uid,display_name,true from public.sovera_profiles where uid between 910001 and 910003;
set local role authenticated;
select set_config('request.jwt.claim.sub','bbccddaa-1111-4000-8000-000000000001',true);
do $$ declare affected int;begin
 insert into public.sovera_user_follows(follower_id,following_id) values(auth.uid(),'bbccddaa-1111-4000-8000-000000000002');
 delete from public.sovera_user_follows where follower_id=auth.uid() and following_id='bbccddaa-1111-4000-8000-000000000002';
 get diagnostics affected=row_count;if affected<>1 then raise exception 'Unfollow failed';end if;
 insert into public.sovera_direct_messages(sender_id,recipient_id,body) values(auth.uid(),'bbccddaa-1111-4000-8000-000000000002','private fixture');
 if(select count(*) from public.sovera_direct_messages where body='private fixture')<>1 then raise exception 'Sender cannot read own message';end if;
 begin insert into public.sovera_direct_messages(sender_id,recipient_id,body) values('bbccddaa-1111-4000-8000-000000000002','bbccddaa-1111-4000-8000-000000000003','forged');raise exception 'Forged sender accepted';exception when insufficient_privilege then null;end;
 begin insert into public.sovera_profile_gifts(recipient_id,gift_key) values(auth.uid(),'Heart');raise exception 'Self credit accepted';exception when insufficient_privilege then null;end;
 update public.sovera_member_cards set medal_styles=array['gold'] where user_id=auth.uid();
 update public.sovera_member_cards set medal_styles=array['gold'] where user_id='bbccddaa-1111-4000-8000-000000000002';get diagnostics affected=row_count;if affected<>0 then raise exception 'Changed other member medals';end if;
 update public.sovera_profiles set display_name='Synced name' where id=auth.uid();
 if(select display_name from public.sovera_member_cards where user_id=auth.uid())<>'Synced name' then raise exception 'Shared card did not synchronize';end if;
end $$;
select set_config('request.jwt.claim.sub','bbccddaa-1111-4000-8000-000000000002',true);
do $$ begin if(select count(*) from public.sovera_direct_messages where body='private fixture')<>1 then raise exception 'Recipient cannot read';end if;end $$;
select set_config('request.jwt.claim.sub','bbccddaa-1111-4000-8000-000000000003',true);
do $$ begin if exists(select 1 from public.sovera_direct_messages where body='private fixture') then raise exception 'Outsider can read private message';end if;end $$;
reset role;
rollback;
