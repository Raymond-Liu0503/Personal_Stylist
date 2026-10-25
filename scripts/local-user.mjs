import {execFileSync} from 'node:child_process';
import {randomBytes} from 'node:crypto';
import {createClient} from '@supabase/supabase-js';

// Read keys from the running local CLI, never from hosted project configuration.
const status=JSON.parse(execFileSync(process.platform==='win32'?'npx.cmd':'npx',['supabase','status','-o','json'],{encoding:'utf8',stdio:['ignore','pipe','inherit']}));
const url=new URL(status.API_URL);
if(!['localhost','127.0.0.1'].includes(url.hostname)||url.protocol!=='http:'||url.port!=='54321')throw new Error('Expected local Supabase on port 54321.');
const client=createClient(url.href,status.SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
const email=`tester-${randomBytes(4).toString('hex')}@example.com`;
const password=randomBytes(18).toString('base64url');
const {data,error}=await client.auth.admin.createUser({email,password,email_confirm:true});
if(error)throw new Error(`Could not create local user: ${error.message}`);
const access=await client.from('beta_access').insert({user_id:data.user.id,enabled:true,daily_quota_exempt:true});
if(access.error){await client.auth.admin.deleteUser(data.user.id);throw new Error('Could not enable local beta access. Apply the database migrations first.');}
console.log(`Local test account created (unlimited daily analyses; monthly budget still applies; no consent pre-accepted).\nEmail: ${email}\nPassword: ${password}\nUse these in the app's Local test login. Apple account-deletion testing still requires an Apple account.`);
