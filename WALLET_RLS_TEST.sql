begin;
insert into auth.users(id) values ('aabbccdd-0000-4000-8000-000000000001'),('aabbccdd-0000-4000-8000-000000000002');
insert into public.sovera_profiles(id,display_name) values ('aabbccdd-0000-4000-8000-000000000001','RLS test one'),('aabbccdd-0000-4000-8000-000000000002','RLS test two');
insert into public.sovera_wallets(user_id) values ('aabbccdd-0000-4000-8000-000000000001'),('aabbccdd-0000-4000-8000-000000000002');
insert into public.sovera_wallet_entries(user_id,coin_delta,diamond_delta,kind,reference) values
 ('aabbccdd-0000-4000-8000-000000000001',100,0,'recharge','rollback-test-credit'),
 ('aabbccdd-0000-4000-8000-000000000001',-20,10,'adjustment','rollback-test-debit'),
 ('aabbccdd-0000-4000-8000-000000000002',999,0,'recharge','rollback-test-other');
insert into public.sovera_coin_sellers(seller_uid,display_name,country,published) select uid,display_name,'Oman',id='aabbccdd-0000-4000-8000-000000000001' from public.sovera_profiles where id in ('aabbccdd-0000-4000-8000-000000000001','aabbccdd-0000-4000-8000-000000000002');
set local role authenticated;
select set_config('request.jwt.claim.sub','aabbccdd-0000-4000-8000-000000000001',true);
do $$ begin
 if (select count(*) from public.sovera_wallets)<>1 then raise exception 'wallet isolation failed';end if;
 if (select count(*) from public.sovera_wallet_entries)<>2 then raise exception 'ledger isolation failed';end if;
 if (select coins from public.sovera_wallet_balances)<>'80' or (select diamonds from public.sovera_wallet_balances)<>'10' then raise exception 'balance sum failed';end if;
 if (select count(*) from public.sovera_coin_sellers)<>1 then raise exception 'published filter failed';end if;
 begin
  update public.sovera_wallet_entries set coin_delta=99999;
  raise exception 'client ledger write allowed';
 exception when insufficient_privilege then null;end;
 begin
  update public.sovera_coin_sellers set published=true;
  raise exception 'client seller approval allowed';
 exception when insufficient_privilege then null;end;
end $$;
reset role;
set local role anon;
do $$ begin
 if (select count(*) from public.sovera_coin_sellers)<>1 then raise exception 'guest published filter failed';end if;
 begin
  perform * from public.sovera_wallets;
  raise exception 'guest wallet access allowed';
 exception when insufficient_privilege then null;end;
end $$;
reset role;
rollback;
