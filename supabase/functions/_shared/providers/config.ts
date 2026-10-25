import { assertInputBound, assertReservation } from './budget.ts';
import { ApiError } from '../security/errors.ts';
import { readLimited } from '../security/input.ts';
import { MockProvider } from './mock.ts';
import { OpenRouterProvider } from './openrouter.ts';
import { productionModel, comparisonModels, selections, profileFor, type Selection, type AnalysisProfile } from '../agents/model-config.ts';
export const MODEL=productionModel.id;
export type {Selection} from '../agents/model-config.ts';
type Env=(name:string)=>string|undefined;
const disabled=()=>new ApiError('DISABLED',503,'The analysis provider configuration could not be verified.');
export async function analysisOptions(env:Env,signal:AbortSignal){
 const profiles=await Promise.all(selections.map(async selection=>{
  let enabled=false;
  try{await selectedProvider(env,signal,selection);enabled=(env('AI_PROVIDER')??'mock')==='mock'?env('APP_ENV')==='local'&&env('ANALYSIS_ENABLED')==='true'&&env('OUTFIT_ENABLED')==='true':env('ANALYSIS_ENABLED')==='true'&&env('OUTFIT_ENABLED')==='true'&&env('STYLIST_PROFILES_ENABLED')==='true'&&env(`STYLIST_${selectedProfile(env,selection).id.replaceAll('-','_').toUpperCase()}_ENABLED`)==='true'&&env(`STYLIST_${selectedProfile(env,selection).id.replaceAll('-','_').toUpperCase()}_INPUT_BOUND_APPROVED`)==='true';}catch{/* Isolate unavailable profiles. */}
  return {...selection,enabled,unavailableReason:enabled?null:'This analysis option is temporarily unavailable.'};
 }));
 return {profiles};
}
// Expert is temporarily disabled while its slower and more expensive route is reviewed.
// Keep the profile contract intact so it can be re-enabled deliberately later.
export function canUseStylistTier(tier:Selection['stylistTier']):boolean{return tier==='everyday';}
export async function selectedProvider(env:Env,signal:AbortSignal,selection:Selection,fetcher:typeof fetch=fetch){
 if(!canUseStylistTier(selection.stylistTier))throw disabled();
 const profile=selectedProfile(env,selection);
 if((env('AI_PROVIDER')??'mock')==='mock'){
  if(env('APP_ENV')!=='local')throw disabled();
  return new MockProvider(env('MOCK_SCENARIO')??'success');
 }
 const key=env('OPENROUTER_API_KEY')?.trim();
 if(env('AI_PROVIDER')!=='openrouter'||!key||/\s/.test(key)||env('OPENROUTER_CONFIG_APPROVED')!=='true'||env('STYLIST_PROFILES_ENABLED')!=='true'||env(`STYLIST_${profile.id.replaceAll('-','_').toUpperCase()}_ENABLED`)!=='true')throw disabled();
 // Fail closed until a reviewed bound for image tokens and text tokenization is recorded.
 if(env(`STYLIST_${profile.id.replaceAll('-','_').toUpperCase()}_INPUT_BOUND_APPROVED`)!=='true')throw disabled();
 assertReservation(profile);
 await cachedPreflight(key,profile,signal,fetcher);
 const provider=new OpenRouterProvider(key,[...profile.providers],fetcher,profile.model,profile.tokenParameter);
 let calls=0;
 return {model:provider.model,generate:async(input:Parameters<typeof provider.generate>[0])=>{
  if(env('STYLIST_PROFILES_ENABLED')!=='true'||env(`STYLIST_${profile.id.replaceAll('-','_').toUpperCase()}_ENABLED`)!=='true'||env(`STYLIST_${profile.id.replaceAll('-','_').toUpperCase()}_INPUT_BOUND_APPROVED`)!=='true')throw disabled();
  assertInputBound(input);
  if(++calls>profile.maxCalls||input.maxOutputTokens>profile.maxOutputTokens)throw disabled();
  return provider.generate(input);
 }};
}
export function selectedProfile(env:Env,selection:Selection):AnalysisProfile{
 try{return profileFor(selection,selection.stylistTier==='everyday'&&selection.analysisDepth==='quick'&&env('STYLIST_EVERYDAY_QUICK_LEGACY')==='true');}catch{throw disabled();}
}
const profileChecks=new Map<string,{expires:number;pending?:Promise<void>}>();
const fetcherIDs=new WeakMap<typeof fetch,number>();let nextFetcherID=0;
async function cachedPreflight(key:string,profile:AnalysisProfile,signal:AbortSignal,fetcher:typeof fetch){
 signal.throwIfAborted();
 if(!fetcherIDs.has(fetcher))fetcherIDs.set(fetcher,++nextFetcherID);
 const cacheKey=JSON.stringify([key,profile,fetcherIDs.get(fetcher)]);
 let entry=profileChecks.get(cacheKey);
 if(!entry||entry.expires<Date.now()&&!entry.pending){
  entry={expires:0};const current=entry;
  current.pending=preflightProfile(key,profile,AbortSignal.timeout(8000),fetcher).then(()=>{current.expires=Date.now()+300000;current.pending=undefined;},()=>{profileChecks.delete(cacheKey);throw disabled();});
  profileChecks.set(cacheKey,current);
 }
 if(entry.pending)await new Promise<void>((resolve,reject)=>{
  const abort=()=>{cleanup();reject(signal.reason);};const cleanup=()=>signal.removeEventListener('abort',abort);
  signal.addEventListener('abort',abort,{once:true});
  entry!.pending!.then(()=>{cleanup();resolve();},e=>{cleanup();reject(e);});
  if(signal.aborted)abort();
 });
 signal.throwIfAborted();
}
async function preflightProfile(key:string,profile:AnalysisProfile,signal:AbortSignal,fetcher:typeof fetch){
 const bounded=AbortSignal.any([signal,AbortSignal.timeout(8000)]);
 const get=async(path:string,auth=false)=>{const response=await fetcher(`https://openrouter.ai/api/v1/${path}`,{signal:bounded,headers:auth?{Authorization:`Bearer ${key}`}:{}});if(!response.ok){await response.body?.cancel();throw disabled();}return JSON.parse(new TextDecoder().decode(await readLimited(response.body,4*1024*1024,bounded)));};
 try{
  const [model,zdr,credentials,catalog]=await Promise.all([get(`models/${profile.model}/endpoints`),get('endpoints/zdr'),get('key',true),get('models')]);
  validateRoute(model,zdr,[...profile.providers],profile.model,profile);
  const listed=catalog.data?.find((m:{id:string})=>m.id===profile.model);
  if(!listed?.reasoning?.supported_efforts?.includes(profile.reasoningEffort))throw disabled();
  if(!credentials.data||credentials.data.limit_remaining!==null&&typeof credentials.data.limit_remaining!=='undefined'&&credentials.data.limit_remaining<=0)throw disabled();
 }catch{throw disabled();}
}
export const REQUIRED_PARAMETERS=['tools','tool_choice','response_format','structured_outputs','max_tokens','reasoning','temperature'];
export const requiredParameters=(profile:AnalysisProfile)=>['response_format','structured_outputs',profile.tokenParameter,'reasoning',...(profile.temperature===undefined?[]:['temperature'])];
export function providerConfig(env:Env){
 const mode=env('AI_PROVIDER')??'mock';
 if(mode==='mock'){if(env('APP_ENV')!=='local')throw disabled();return {mode:'mock' as const};}
 const key=env('OPENROUTER_API_KEY')?.trim();const model=env('OPENROUTER_MODEL')??MODEL;
 const providers=(env('OPENROUTER_PROVIDERS')??'').split(',').map(s=>s.trim());
 const allowedModel=model===MODEL||(env('APP_ENV')==='local'&&comparisonModels.some(candidate=>candidate===model));
 if(mode!=='openrouter'||!key||/\s/.test(key)||!allowedModel||env('OPENROUTER_CONFIG_APPROVED')!=='true'||!providers.length||providers.some(p=>!['google-vertex/global','google-vertex/us','google-vertex/eu'].includes(p))||new Set(providers).size!==providers.length)throw disabled();
 return {mode:'live' as const,key,providers,model};
}
export function validateRoute(model:unknown,zdr:unknown,providers:string[],expectedModel:string=MODEL,profile?:AnalysisProfile){
 const data=model as {data?:{id?:string;architecture?:{input_modalities?:string[]};endpoints?:{tag:string;model_id:string;status:number;supported_parameters:string[];max_completion_tokens:number;pricing?:{prompt?:string;completion?:string;overrides?:unknown[]}}[]}};
 const privacy=zdr as {data?:{tag:string;model_id:string}[]};
 if(data.data?.id!==expectedModel||!data.data.architecture?.input_modalities?.includes('image')||!Array.isArray(data.data.endpoints)||!Array.isArray(privacy.data))throw disabled();
 for(const tag of providers){const endpoint=data.data.endpoints.find(e=>e.tag===tag&&e.model_id===expectedModel);
  if(profile&&(!endpoint?.pricing||!Number.isFinite(Number(endpoint.pricing.prompt))||!Number.isFinite(Number(endpoint.pricing.completion))||Number(endpoint.pricing.prompt)<0||Number(endpoint.pricing.completion)<0||Number(endpoint.pricing.prompt)>profile.inputPrice||Number(endpoint.pricing.completion)>profile.outputPrice))throw disabled();
  // Reject overrides which could invalidate the approved <=64K prompt cost bound.
  if(profile&&endpoint?.pricing?.overrides?.some(o=>{const override=o as {min_prompt_tokens?:number};return typeof override.min_prompt_tokens!=='number'||override.min_prompt_tokens<=65536;}))throw disabled();
  if(!endpoint||endpoint.status!==0||endpoint.max_completion_tokens<(profile?.maxOutputTokens??productionModel.maxOutputTokens)||!(profile?requiredParameters(profile):REQUIRED_PARAMETERS).every(p=>endpoint.supported_parameters?.includes(p))||!privacy.data.some(e=>e.tag===tag&&e.model_id===expectedModel))throw disabled();
 }
}
// Cache only successful checks briefly; changed configuration always forces a fresh check.
let cached:{key:string;providers:string;model:string;expires:number}|undefined;
export async function configuredProvider(env:Env,signal:AbortSignal,fetcher:typeof fetch=fetch){
 const config=providerConfig(env);if(config.mode==='mock')return new MockProvider(env('MOCK_SCENARIO')??'success');
 const providers=config.providers.join(',');
 if(!cached||cached.key!==config.key||cached.providers!==providers||cached.model!==config.model||cached.expires<Date.now()){
  const bounded=AbortSignal.any([signal,AbortSignal.timeout(8000)]);
  const get=async(path:string,auth=false)=>{const response=await fetcher(`https://openrouter.ai/api/v1/${path}`,{signal:bounded,headers:auth?{Authorization:`Bearer ${config.key}`}:{}});if(!response.ok){await response.body?.cancel();throw disabled();}return JSON.parse(new TextDecoder().decode(await readLimited(response.body,4*1024*1024,bounded)));};
  try{const [model,zdr,credentials]=await Promise.all([get(`models/${config.model}/endpoints`),get('endpoints/zdr'),get('key',true)]);validateRoute(model,zdr,config.providers,config.model);if(!credentials.data||credentials.data.limit_remaining!==null&&typeof credentials.data.limit_remaining!=='undefined'&&credentials.data.limit_remaining<=0)throw disabled();}
  catch{throw disabled();}
  cached={key:config.key,providers,model:config.model,expires:Date.now()+300000};
 }
 return new OpenRouterProvider(config.key,config.providers,fetcher,config.model);
}
