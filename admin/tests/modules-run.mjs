import {PGlite} from '@electric-sql/pglite';
import {readFileSync,writeFileSync} from 'node:fs';
const db=new PGlite();
const root=new URL('../../',import.meta.url).pathname;
await db.exec(readFileSync(root+'admin/tests/fixture.sql','utf8'));
for(const f of ['WALLET_SCHEMA.sql','PEOPLE_SCHEMA.sql','ROOMS_SCHEMA.sql','RESELLER_SCHEMA.sql'])await db.exec(readFileSync(root+f,'utf8'));
await db.exec(`alter table public.sovera_member_cards add column avatar_url text,add column bio text default '',add column medal_styles text[] default '{}';
alter table public.sovera_member_cards drop constraint sovera_member_cards_uid_fkey;alter table public.sovera_member_cards add constraint sovera_member_cards_uid_fkey foreign key(uid) references public.sovera_profiles(uid) on update cascade on delete cascade;
alter table public.sovera_coin_sellers drop constraint sovera_coin_sellers_seller_uid_fkey;alter table public.sovera_coin_sellers add constraint sovera_coin_sellers_seller_uid_fkey foreign key(seller_uid) references public.sovera_profiles(uid) on update cascade on delete cascade;
insert into auth.users(id,email) values('00000000-0000-4000-8000-000000000001','fixture@example.test');insert into public.sovera_profiles(id)values('00000000-0000-4000-8000-000000000001');insert into public.sovera_member_cards(user_id,uid,display_name)select id,uid,display_name from public.sovera_profiles;
`);
await db.exec('begin');
try{await db.exec(readFileSync(root+'admin/backend/schema.sql','utf8'));await db.exec('commit');}catch(e){console.error('Migration failure:',e.message);process.exit(1);}
console.log('UP migration passed');
const state=await db.query('select uid,vip_id,is_banned from public.sovera_profiles');console.log(state.rows);

await db.exec(`create table storage.objects(id uuid,bucket_id text,name text);alter table storage.objects enable row level security;create function storage.foldername(text) returns text[] language sql as $$select string_to_array($1,'/')$$;`);
await db.exec(readFileSync(root+'admin/backend/modules.sql','utf8'));console.log('Modules migration passed');
await db.exec(readFileSync(root+'admin/tests/modules-test.sql','utf8'));console.log('Modules authorization and accounting tests passed');await db.close();
