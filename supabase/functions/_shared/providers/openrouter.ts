import type {Provider,Generation} from './types.ts';
import { productionModel } from '../agents/model-config.ts';
import { ApiError } from '../security/errors.ts';
import { readLimited } from '../security/input.ts';
function base64(bytes:Uint8Array){let str='';for(let i=0;i<bytes.length;i+=8192)str+=String.fromCharCode(...bytes.subarray(i,i+8192));return btoa(str);}
export class OpenRouterProvider implements Provider {
 constructor(private key:string,private providers:string[],private fetcher:typeof fetch=fetch,public model:string=productionModel.id,private tokenParameter:'max_tokens'|'max_completion_tokens'='max_tokens') {if(!key||!providers.length)throw new ApiError('DISABLED',503);}
 async generate(input:Parameters<Provider['generate']>[0]):Promise<Generation>{
  const messages=input.messages.map((m,i)=>i===1&&input.image?{...m,content:[{type:'text',text:m.content},{type:'image_url',image_url:{url:`data:image/jpeg;base64,${base64(input.image)}`}}]}:m);
  for(let attempt=0;attempt<2;attempt++) {
    // Only an explicit HTTP 429 rejection is retried. Ambiguous I/O and timeouts propagate.
    const res=await this.fetcher('https://openrouter.ai/api/v1/chat/completions',{method:'POST',signal:input.signal,headers:{Authorization:`Bearer ${this.key}`,'Content-Type':'application/json'},body:JSON.stringify({model:this.model,messages,provider:{only:this.providers,allow_fallbacks:false,zdr:true,data_collection:'deny',require_parameters:true},response_format:{type:'json_schema',json_schema:{name:'outfit_assessment',strict:true,schema:input.schema}},...(input.tools.length?{tools:input.tools,tool_choice:'auto'}:{}),[this.tokenParameter]:input.maxOutputTokens,reasoning:{effort:input.reasoningEffort,exclude:true},...(input.temperature===undefined?{}:{temperature:input.temperature}),stream:false})});
    if(res.status===429&&attempt===0){await res.body?.cancel();continue;}
    if(!res.ok){
      // Log only bounded operational metadata, never upstream messages which may echo user content.
      let upstreamCode:number|undefined;let category='unknown';
      try{
        const errorBody=JSON.parse(new TextDecoder().decode(await readLimited(res.body,32*1024,input.signal)));
        if(Number.isInteger(errorBody.error?.code))upstreamCode=errorBody.error.code;
        const message=typeof errorBody.error?.message==='string'?errorBody.error.message.toLowerCase():'';
        category=message.includes('no endpoints')?'no_matching_endpoints':message.includes('credit')?'credits':message.includes('rate limit')?'rate_limit':message.includes('schema')?'schema':message.includes('reasoning')?'reasoning':message.includes('provider returned')?'upstream_provider_error':message.includes('auth')?'authentication':'unknown';
      }catch{/* Diagnostics must not replace the original failure. */}
      console.warn(JSON.stringify({event:'provider_rejection',model:this.model,providers:this.providers,httpStatus:res.status,upstreamCode,category}));
      throw new ApiError('PROVIDER_UNAVAILABLE',503,'The analysis service is unavailable.');
    }
    const bytes=await readLimited(res.body,128*1024,input.signal);
    let body;try{body=JSON.parse(new TextDecoder().decode(bytes));}catch{throw new ApiError('INVALID_MODEL_OUTPUT',502);}
    const message=body.choices?.[0]?.message;
    const u=body.usage;
    const validUsage=Number.isSafeInteger(u?.prompt_tokens)&&u.prompt_tokens>=0&&Number.isSafeInteger(u?.completion_tokens)&&u.completion_tokens>=0;
    const usage={inputTokens:validUsage?u.prompt_tokens:0,outputTokens:validUsage?u.completion_tokens:0,costMicrodollars:validUsage&&typeof u?.cost==='number'&&Number.isFinite(u.cost)&&u.cost>=0?Math.ceil(u.cost*1e6):null};
    // Preserve billable usage even when the completion cannot be published.
    const finishReason=body.choices?.[0]?.finish_reason;
    let output;try{output=!body.error&&finishReason!=='length'&&message?.content?JSON.parse(message.content):undefined;}catch{output=undefined;}
    if(output===undefined){
      const hasContent=!!message?.content;
      console.warn(JSON.stringify({event:'model_output_debug',model:this.model,finishReason,outputPresent:hasContent,schemaName:(input.schema as any)?.type,error:body.error?JSON.stringify(body.error).slice(0,200):'none'}));
    }
    return {output,toolCalls:message?.tool_calls,usage};
  }
  throw new ApiError('PROVIDER_UNAVAILABLE',503);
 }
}
