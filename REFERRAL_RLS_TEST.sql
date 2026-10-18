begin;
insert into auth.users(id) values ('ccddffaa-0000-4000-8000-000000000001'),('ccddffaa-0000-4000-8000-000000000002'),('ccddffaa-0000-4000-8000-000000000003');
insert into public.sovera_profiles(id,display_name) values ('ccddffaa-0000-4000-8000-000000000001','Referral test 1'),('ccddffaa-0000-4000-8000-000000000002','Referral test 2'),('ccddffaa-0000-4000-8000-000000000003','Referral test 3');
insert into public.sovera_referral_codes(user_id) values ('ccddffaa-0000-4000-8000-000000000001'),('ccddffaa-0000-4000-8000-000000000002');
select set_config('test.code1',(select code from public.sovera_referral_codes where user_id='ccddffaa-0000-4000-8000-000000000001'),true);
select set_config('test.code2',(select code from public.sovera_referral_codes where user_id='ccddffaa-0000-4000-8000-000000000002'),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','ccddffaa-0000-4000-8000-000000000002',true);
do $$ begin
 if (select count(*) from public.sovera_referral_codes)<>1 then raise exception 'code privacy failed';end if;
 begin insert into public.sovera_referrals(referral_code) values(current_setting('test.code2'));raise exception 'self allowed'; exception when insufficient_privilege then null;end;
 insert into public.sovera_referrals(referral_code) values(current_setting('test.code1'));
 begin insert into public.sovera_referrals(referral_code) values(current_setting('test.code1'));raise exception 'duplicate allowed'; exception when unique_violation then null;end;
 begin delete from public.sovera_referrals;raise exception 'delete allowed';exception when insufficient_privilege then null;end;
 begin insert into public.sovera_referrals(referred_id,referral_code) values('ccddffaa-0000-4000-8000-000000000003',current_setting('test.code1'));raise exception 'forgery allowed';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','ccddffaa-0000-4000-8000-000000000003',true);
do $$ begin
 if (select count(*) from public.sovera_referrals)<>0 then raise exception 'claim privacy failed';end if;
 begin insert into public.sovera_referrals(referral_code) values('SV000000000000');raise exception 'invalid code allowed';exception when foreign_key_violation then null;end;
end $$;
select set_config('request.jwt.claim.sub','ccddffaa-0000-4000-8000-000000000001',true);
do $$ begin if (select count(*) from public.sovera_referrals)<>1 then raise exception 'inviter count failed';end if;end $$;
reset role;
rollback;
