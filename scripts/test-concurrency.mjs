import {spawn} from 'node:child_process';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
// Local Docker only. Uses an isolated test user and cleans it up; no real images or prompts.
const container=process.env.STYLIST_DB_CONTAINER??'supabase_db_personal-stylist';
function sql(query){return new Promise((resolve,reject)=>{const p=spawn('docker',['exec','-i',container,'psql','-U','postgres','-d','postgres','-At','-v','ON_ERROR_STOP=1'],{stdio:['pipe','pipe','pipe']});let out='',err='';p.stdout.on('data',s=>out+=s);p.stderr.on('data',s=>err+=s);p.on('error',reject);p.on('exit',code=>code?reject(new Error(err)):resolve(out.trim()));p.stdin.end(query);});}
const uid=randomUUID();
try{
 await sql(`insert into auth.users(id,email) values ('${uid}','concurrency@example.invalid'); insert into beta_access values ('${uid}',true); insert into consents(user_id,policy_version,accepted,adult_confirmed) values ('${uid}','2026-09-01',true,true);`);
 const ids=Array.from({length:8},()=>randomUUID());
 const results=await Promise.all(ids.map(id=>sql(`select claim_analysis('${uid}','${id}','{}');`)));
 assert.equal(results.filter(x=>x==='OK').length,1);assert.equal(results.filter(x=>x==='ANALYSIS_ACTIVE').length,7);
 const winner=ids[results.indexOf('OK')];
 assert.equal(await sql(`select dispatch_analysis('${uid}','${winner}');`),'t');
 await Promise.all(Array.from({length:8},()=>sql(`select settle_analysis('${uid}','${winner}',0);`)));
 assert.equal(await sql(`select dispatched_count from usage_daily where user_id='${uid}';`),'1');
 for(let i=0;i<2;i++){const id=randomUUID();assert.equal(await sql(`select claim_analysis('${uid}','${id}','{}');`),'OK');await sql(`select dispatch_analysis('${uid}','${id}');select settle_analysis('${uid}','${id}',0);`);}
 assert.equal(await sql(`select claim_analysis('${uid}','${randomUUID()}','{}');`),'QUOTA_EXHAUSTED');
 console.log('PASS: concurrent reservation, repeated settlement, daily quota');
}finally{await sql(`delete from auth.users where id='${uid}';`);}
