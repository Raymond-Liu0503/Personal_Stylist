import type {z} from 'zod';
import type {ModelSettings} from './config.ts';
import {OpenRouterProvider} from '../../supabase/functions/_shared/providers/openrouter.ts';
import {MockProvider} from '../../supabase/functions/_shared/providers/mock.ts';
import type {Provider} from '../../supabase/functions/_shared/providers/types.ts';
import {readLimited} from '../../supabase/functions/_shared/security/input.ts';
export type Route={provider:Provider;bound:number;snapshot:unknown};
export async function verifiedProvider(settings:z.infer<typeof ModelSettings>,live:boolean,signal:AbortSignal):Promise<Route>{
 if(!live){const mock=new MockProvider();return {bound:0,snapshot:{mock:true,settings},provider:{model:settings.model,generate:async input=>{
  if((input.schema as {properties?:{verdicts?:unknown}}).properties?.verdicts){const context=JSON.parse(input.messages[1].content as string);return {output:{verdicts:context.candidates.map((c:{id:string;revision:number})=>({id:c.id,revision:c.revision,verdict:'pass',evidence:'Mock review only',reason:'No visual inference performed'})),assessmentValid:true,assessmentIssues:[],missedOpportunity:null},usage:{inputTokens:0,outputTokens:0,costMicrodollars:0}};}
  return mock.generate(input);
 }}};}
 if(process.env.OPENROUTER_CONFIG_APPROVED!=='true'||process.env.EVAL_RIGHTS_CONFIRMED!=='true'||!process.env.OPENROUTER_API_KEY)throw new Error('Live evaluation requires provider approval, rights confirmation and server-side credentials');
 const get=async(path:string)=>{const r=await fetch(`https://openrouter.ai/api/v1/${path}`,{signal:AbortSignal.any([signal,AbortSignal.timeout(8000)])});if(!r.ok)throw new Error('Endpoint verification failed');return JSON.parse(new TextDecoder().decode(await readLimited(r.body,4*1024*1024,signal)));};
 const [model,zdr]=await Promise.all([get(`models/${settings.model}/endpoints`),get('endpoints/zdr')]);
 const endpoint=model.data?.endpoints?.find((e:any)=>e.tag===settings.route&&e.model_id===settings.model);
 const required=['response_format','structured_outputs','max_tokens','reasoning','temperature'];
 if(model.data?.id!==settings.model||!model.data?.architecture?.input_modalities?.includes('image')||!endpoint||endpoint.status!==0||!required.every(p=>endpoint.supported_parameters?.includes(p))||endpoint.max_completion_tokens<settings.maxOutputTokens||!zdr.data?.some((e:any)=>e.tag===settings.route&&e.model_id===settings.model))throw new Error('Selected vision/structured-output/ZDR route is unavailable');
 // Reserve the complete context-window price, including long-context tiers. This is deliberately
 // conservative: do not guess image-token counts or silently expand a $25 pilot to fit the matrix.
 const tiers=[endpoint.pricing,...(endpoint.pricing?.overrides??[])];
 const rate=(key:string)=>Math.max(...tiers.map((p:any)=>Number(p[key]??endpoint.pricing?.[key])));
 const prompt=Math.max(rate('prompt'),Number(endpoint.pricing?.image??0)),completion=Math.max(rate('completion'),Number(endpoint.pricing?.internal_reasoning??0));
 const context=Number(endpoint.context_length);
 if(!Number.isFinite(prompt)||!Number.isFinite(completion)||prompt<0||completion<0||!Number.isSafeInteger(context)||context<=0)throw new Error('Cannot bound route cost');
 const requestPrice=Number(endpoint.pricing?.request??0);if(!Number.isFinite(requestPrice)||requestPrice<0)throw new Error('Invalid request price');
 const bound=Math.ceil((context*prompt+settings.maxOutputTokens*completion+requestPrice)*1e6);
 return {provider:new OpenRouterProvider(process.env.OPENROUTER_API_KEY,[settings.route],fetch,settings.model),bound,snapshot:{verifiedAt:new Date().toISOString(),endpoint,settings}};
}
