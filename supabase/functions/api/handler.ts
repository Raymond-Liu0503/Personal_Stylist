import { createClient } from '@supabase/supabase-js';
import { z } from 'zod';
import { mergeAssessmentContext,POLICY_VERSION,PreferencesSchema,ConsentSchema,SaveReportSchema,FeedbackSchema,DeleteAccountSchema,type ErrorCode } from '../../../packages/contracts/src/index.ts';
import { ApiError } from '../_shared/security/errors.ts';
import { readLimited,parseAnalysis } from '../_shared/security/input.ts';
import { signReceipt,verifyReceipt } from '../_shared/security/receipts.ts';
import { revokeAppleGrant } from '../_shared/security/apple.ts';
import { configuredProvider } from '../_shared/providers/config.ts';
import { runOutfit } from '../_shared/agents/runtime.ts';
import { assessmentVersions } from '../_shared/agents/registry.ts';
import { recentTechniqueMemory,resolveSuggestionTechnique } from '../_shared/agents/suggestions.ts';
export type Env=(name:string)=>string|undefined;
const headers={'Content-Type':'application/json','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'};
const json=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers});
function checked<T>(r:{data:T;error:unknown}){if(r.error)throw new ApiError('INTERNAL',500);return r.data;}
async function body<T>(req:Request,schema:z.ZodType<T>,signal:AbortSignal){try{return schema.parse(JSON.parse(new TextDecoder().decode(await readLimited(req.body,40000,signal))));}catch(e){if(e instanceof ApiError)throw e;throw new ApiError('INVALID_INPUT',400,'Check the submitted information.');}}
export function createHandler(env:Env){return async(req:Request)=>{
 const started=Date.now();let requestId:string|undefined;let status='success';
 const deadline=AbortSignal.timeout(45000);const signal=AbortSignal.any([deadline,req.signal]);
 try {
  const url=new URL(req.url);const prefix='/api/v1';const full=url.pathname.replace(/^\/functions\/v1/,'');if(!full.startsWith(prefix+'/'))throw new ApiError('NOT_FOUND',404);const path=full.slice(prefix.length);
  const bearer=req.headers.get('authorization');if(!bearer?.match(/^Bearer [^\s]+$/))throw new ApiError('UNAUTHENTICATED',401,'Please sign in again.');
  const base=env('SUPABASE_URL')!,adminKey=env('SUPABASE_SERVICE_ROLE_KEY')!,publicKey=env('SUPABASE_ANON_KEY')??env('SUPABASE_PUBLISHABLE_KEY')!;
  const boundedFetch:typeof fetch=(input,init)=>{
   const requestInit=init as RequestInit|undefined;
   return fetch(input,{...requestInit,signal:AbortSignal.any([signal,...(requestInit?.signal?[requestInit.signal]:[])])});
  };
  const userDb=createClient(base,publicKey,{global:{headers:{Authorization:bearer},fetch:boundedFetch},auth:{persistSession:false,autoRefreshToken:false}});
  const admin=createClient(base,adminKey,{global:{fetch:boundedFetch},auth:{persistSession:false,autoRefreshToken:false}});
  const auth=await userDb.auth.getUser(bearer.slice(7));if(auth.error||!auth.data.user)throw new ApiError('UNAUTHENTICATED',401,'Please sign in again.');const user=auth.data.user;const uid=user.id;
  if(path==='/bootstrap'&&req.method==='GET'){
   const results=await Promise.all([userDb.from('profiles').select('preferences').eq('user_id',uid).maybeSingle(),userDb.from('consents').select('accepted,policy_version').eq('user_id',uid).order('created_at',{ascending:false}).order('id',{ascending:false}).limit(1).maybeSingle(),userDb.from('beta_access').select('enabled,daily_quota_exempt').eq('user_id',uid).maybeSingle(),userDb.from('usage_daily').select('dispatched_count').eq('user_id',uid).eq('day',new Date().toISOString().slice(0,10)).maybeSingle()]);
   const profile=checked(results[0]),consent=checked(results[1]),beta=checked(results[2]),usage=checked(results[3]);
   let available=false;try{await configuredProvider(env,signal,boundedFetch);available=true;}catch{/* Fail closed; bootstrap still exposes account access. */}
   return json({dailyQuotaExempt:beta?.daily_quota_exempt===true,analysisMode:env('AI_PROVIDER')==='openrouter'?'live':'mock',profile:profile?.preferences??{},policyVersion:POLICY_VERSION,consentAccepted:consent?.accepted===true&&consent.policy_version===POLICY_VERSION,features:{outfit:available&&env('ANALYSIS_ENABLED')==='true'&&env('OUTFIT_ENABLED')==='true'},remainingQuota:Math.max(0,3-(usage?.dispatched_count??0)),betaAccess:beta?.enabled===true});
  }
  if(path==='/profile'&&req.method==='PUT'){const preferences=await body(req,PreferencesSchema,signal);checked(await admin.from('profiles').upsert({user_id:uid,preferences,updated_at:new Date().toISOString()},{onConflict:'user_id'}));return json(preferences);}
  if(path==='/consents'&&req.method==='POST'){const consent=await body(req,ConsentSchema,signal);checked(await admin.from('consents').insert({user_id:uid,policy_version:consent.policyVersion,accepted:consent.accepted,adult_confirmed:consent.adultConfirmed}));return json({accepted:consent.accepted});}
  if(path==='/analyze/outfit'&&req.method==='POST'){
   if(env('ANALYSIS_ENABLED')!=='true'||env('OUTFIT_ENABLED')!=='true')throw new ApiError('DISABLED',503,'Analysis is temporarily paused.');
   const key=req.headers.get('idempotency-key');if(!z.string().uuid().safeParse(key).success)throw new ApiError('INVALID_INPUT');requestId=key!;
   const access=checked(await userDb.from('beta_access').select('enabled').eq('user_id',uid).maybeSingle());if(!access?.enabled)throw new ApiError('BETA_REQUIRED',403,'Your beta invitation is not enabled yet.');
   const consent=checked(await userDb.from('consents').select('accepted,policy_version').eq('user_id',uid).order('created_at',{ascending:false}).order('id',{ascending:false}).limit(1).maybeSingle());if(!consent?.accepted||consent.policy_version!==POLICY_VERSION)throw new ApiError('CONSENT_REQUIRED',403,'Accept the current AI-processing policy first.');
   const input=await parseAnalysis(req,signal);
   const prefs=PreferencesSchema.parse(checked(await userDb.from('profiles').select('preferences').eq('user_id',uid).maybeSingle())?.preferences??{});
   // Explicitly saved preferences may supply context; never invent an occasion.
   input.metadata.context=mergeAssessmentContext(prefs,input.metadata.context);
   const provider=await configuredProvider(env,signal,boundedFetch);
   const secret=env('REPORT_SIGNING_SECRET')??'';if(secret.length<32)throw new ApiError('DISABLED',503);
   const claim=checked(await admin.rpc('claim_analysis',{p_user:uid,p_request:requestId,p_versions:assessmentVersions(provider.model),p_reserve:100000}));
   if(claim!=='OK')throw new ApiError(claim as ErrorCode,claim==='CONSENT_REQUIRED'||claim==='BETA_REQUIRED'?403:claim.includes('DUPLICATE')||claim==='ANALYSIS_ACTIVE'?409:429,claim==='DUPLICATE_FINISHED'?'The original analysis finished. Unsaved results cannot be recovered; start a new analysis only if you want another assessment.':'This analysis cannot start. Check consent, quota, or an active submission.');
   let dispatched=false,uncertain=false,known=true,totalCost=0,inputTokens=0,outputTokens=0;
   // Accounting gets a separate bounded signal so client cancellation cannot skip settlement.
   const settle=async(actual:number|null,failed:boolean)=>{const db=createClient(base,adminKey,{global:{fetch:(i,o)=>fetch(i,{...o,signal:AbortSignal.timeout(5000)})},auth:{persistSession:false}});checked(await db.rpc('settle_analysis',{p_user:uid,p_request:requestId,p_actual:actual,p_failed:failed,p_input:inputTokens,p_output:outputTokens}));};
   try{
    signal.throwIfAborted();if(!checked(await admin.rpc('dispatch_analysis',{p_user:uid,p_request:requestId})))throw new ApiError('CONSENT_REQUIRED',403);dispatched=true;
    const measured={model:provider.model,generate:async(args:Parameters<typeof provider.generate>[0])=>{uncertain=true;const result=await provider.generate(args);uncertain=false;return result;}};
    const recentRows=checked(await admin.from('analysis_runs').select('technique_codes').eq('user_id',uid).eq('state','finished').not('technique_codes','is',null).order('updated_at',{ascending:false}).limit(3))??[];
    const recentTechniques=recentTechniqueMemory(recentRows);
    const result=await runOutfit(measured,{...input,runId:requestId,signal,recentTechniques},usage=>{inputTokens+=usage.inputTokens;outputTokens+=usage.outputTokens;if(usage.costMicrodollars===null)known=false;else totalCost+=usage.costMicrodollars;},diagnostic=>console.info(JSON.stringify({requestId,event:'model_validation',...diagnostic})));
    signal.throwIfAborted();await settle(known?totalCost:null,false);
    if(result.kind==='report')checked(await admin.from('analysis_runs').update({technique_codes:result.techniqueCodes}).eq('user_id',uid).eq('request_id',requestId).eq('state','finished'));
    status=result.kind;
    if(result.kind==='retake')return json(result);
    const {techniqueCodes:_techniqueCodes,...publicResult}=result;
    return json({...publicResult,receipt:await signReceipt(secret,uid,result.report)});
   }catch(e){await settle(!dispatched?0:!uncertain&&known?totalCost:null,true).catch(()=>{});throw e;}
  }
  if(path==='/reports'&&req.method==='POST'){
   const data=await body(req,SaveReportSchema,signal);await verifyReceipt(env('REPORT_SIGNING_SECRET')??'',uid,data.report,data.receipt);
   // Unique owner/run makes Save retries idempotent without overwriting a previous saved report.
   const inserted=await admin.from('saved_reports').upsert({user_id:uid,run_id:data.report.runId,schema_version:1,report:data.report},{onConflict:'user_id,run_id',ignoreDuplicates:true});checked(inserted);
   return json(checked(await userDb.from('saved_reports').select('id,created_at,report').eq('run_id',data.report.runId).eq('user_id',uid).single()),201);
  }
  if(path==='/reports'&&req.method==='GET'){
   let query=userDb.from('saved_reports').select('id,created_at,report').eq('user_id',uid).order('created_at',{ascending:false}).order('id',{ascending:false}).limit(21);
   const cursor=url.searchParams.get('cursor');if(cursor){let c;try{c=z.object({at:z.string().datetime({offset:true}),id:z.string().uuid()}).strict().parse(JSON.parse(atob(cursor)));}catch{throw new ApiError('INVALID_INPUT');}query=query.or(`created_at.lt.${c.at},and(created_at.eq.${c.at},id.lt.${c.id})`);}
   const rows=checked(await query)!;const items=rows.slice(0,20);const last=items.at(-1);return json({items,nextCursor:rows.length>20&&last?btoa(JSON.stringify({at:last.created_at,id:last.id})):null});
  }
  const reportMatch=path.match(/^\/reports\/([a-f0-9-]+)$/i);
  if(reportMatch&&['GET','DELETE'].includes(req.method)){
   const id=z.string().uuid().safeParse(reportMatch[1]);if(!id.success)throw new ApiError('INVALID_INPUT');
   const row=checked(await userDb.from('saved_reports').select('id,created_at,report').eq('id',id.data).eq('user_id',uid).maybeSingle());if(!row)throw new ApiError('NOT_FOUND',404);
   if(req.method==='GET')return json(row);checked(await admin.from('saved_reports').delete().eq('id',id.data).eq('user_id',uid));return json({deleted:true});
  }
  if(path==='/feedback'&&req.method==='POST'){
   const data=await body(req,FeedbackSchema,signal);
   if('runId' in data){
    const run=checked(await userDb.from('analysis_runs').select('technique_codes').eq('request_id',data.runId).eq('user_id',uid).eq('state','finished').maybeSingle());
    if(!run)throw new ApiError('NOT_FOUND',404);
    const technique=resolveSuggestionTechnique(run.technique_codes,data.suggestionIndex);
    if(technique===null)throw new ApiError('INVALID_INPUT',400,'That suggestion is not part of this analysis.');
    const duplicate=checked(await userDb.from('feedback').select('id').eq('user_id',uid).eq('run_id',data.runId).eq('suggestion_index',data.suggestionIndex).maybeSingle());
    if(duplicate)throw new ApiError('INVALID_INPUT',409,'Feedback for this suggestion was already received.');
    checked(await admin.from('feedback').insert({user_id:uid,run_id:data.runId,suggestion_index:data.suggestionIndex,technique,helpful:data.helpful,issues:[]}));return json({received:true},201);
   }
   if(data.savedReportId){const owned=checked(await userDb.from('saved_reports').select('id').eq('id',data.savedReportId).eq('user_id',uid).maybeSingle());if(!owned)throw new ApiError('NOT_FOUND',404);}
   checked(await admin.from('feedback').insert({user_id:uid,saved_report_id:data.savedReportId,helpful:data.helpful,issues:data.issues}));return json({received:true},201);
  }
  if(path==='/account'&&req.method==='DELETE'){
   const data=await body(req,DeleteAccountSchema,signal);const subject=user.identities?.find(i=>i.provider==='apple')?.identity_data?.sub;if(typeof subject!=='string')throw new ApiError('REAUTHENTICATION_REQUIRED',401);
   if(!env('APPLE_CLIENT_ID')||!env('APPLE_CLIENT_SECRET'))throw new ApiError('DELETION_PENDING',503,'Account deletion needs the Apple service configuration.');
   await revokeAppleGrant(data.authorizationCode,subject,{clientId:env('APPLE_CLIENT_ID')!,clientSecret:env('APPLE_CLIENT_SECRET')!},signal);
   checked(await admin.from('profiles').upsert({user_id:uid,deletion_stage:'revoked',updated_at:new Date().toISOString()},{onConflict:'user_id'}));
   const deletion=await admin.auth.admin.deleteUser(uid);if(deletion.error)throw new ApiError('DELETION_PENDING',503,'Apple authorisation was revoked. Retry to finish deleting your account.');return json({deleted:true});
  }
  throw new ApiError('NOT_FOUND',404);
 }catch(e){
  const error=signal.aborted?new ApiError('TIMEOUT',504,'The request timed out or was cancelled. An already-started analysis may still count toward your allowance.'):e instanceof ApiError?e:new ApiError('INTERNAL',500,'Something went wrong. Please try again.');status=error.code;return json({error:{code:error.code,message:error.message}},error.status);
 }finally{
  // Never pass an exception, request, user id, prompt, image, or provider response to logging.
  console.info(JSON.stringify({requestId,status,elapsedMs:Date.now()-started}));
 }
};}
