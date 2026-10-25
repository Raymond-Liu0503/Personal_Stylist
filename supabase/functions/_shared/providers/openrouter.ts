import type {Provider,Generation} from './types.ts';
import { productionModel } from '../agents/model-config.ts';
import { ApiError } from '../security/errors.ts';
import { readLimited } from '../security/input.ts';
function base64(bytes:Uint8Array){let str='';for(let i=0;i<bytes.length;i+=8192)str+=String.fromCharCode(...bytes.subarray(i,i+8192));return btoa(str);}
export class OpenRouterProvider implements Provider {
 constructor(private key:string,private providers:string[],private fetcher:typeof fetch=fetch,public model:string=productionModel.id) {if(!key||!providers.length)throw new ApiError('DISABLED',503);}
 async generate(input:Parameters<Provider['generate']>[0]):Promise<Generation>{
  const messages=input.messages.map((m,i)=>i===1&&input.image?{...m,content:[{type:'text',text:m.content},{type:'image_url',image_url:{url:`data:image/jpeg;base64,${base64(input.image)}`}}]}:m);
  for(let attempt=0;attempt<2;attempt++) {
    // Only an explicit HTTP 429 rejection is retried. Ambiguous I/O and timeouts propagate.
    const res=await this.fetcher('https://openrouter.ai/api/v1/chat/completions',{method:'POST',signal:input.signal,headers:{Authorization:`Bearer ${this.key}`,'Content-Type':'application/json'},body:JSON.stringify({model:this.model,messages,provider:{only:this.providers,allow_fallbacks:false,zdr:true,data_collection:'deny',require_parameters:true},response_format:{type:'json_schema',json_schema:{name:'outfit_assessment',strict:true,schema:input.schema}},...(input.tools.length?{tools:input.tools,tool_choice:'auto'}:{}),max_tokens:input.maxOutputTokens,reasoning:{effort:input.reasoningEffort},temperature:input.temperature,stream:false})});
    if(res.status===429&&attempt===0){await res.body?.cancel();continue;}
    if(!res.ok){await res.body?.cancel();throw new ApiError('PROVIDER_UNAVAILABLE',503,'The analysis service is unavailable.');}
    const bytes=await readLimited(res.body,128*1024,input.signal);
    let body;try{body=JSON.parse(new TextDecoder().decode(bytes));}catch{throw new ApiError('INVALID_MODEL_OUTPUT',502);}
    const message=body.choices?.[0]?.message;
    if(!message || body.error)throw new ApiError('INVALID_MODEL_OUTPUT',502);
    const u=body.usage;
    const usage={inputTokens:Number.isSafeInteger(u?.prompt_tokens)?u.prompt_tokens:0,outputTokens:Number.isSafeInteger(u?.completion_tokens)?u.completion_tokens:0,costMicrodollars:typeof u?.cost==='number'&&Number.isFinite(u.cost)&&u.cost>=0?Math.ceil(u.cost*1e6):null};
    let output;try{output=message.content?JSON.parse(message.content):undefined;}catch{output=undefined;}
    return {output,toolCalls:message.tool_calls,usage};
  }
  throw new ApiError('PROVIDER_UNAVAILABLE',503);
 }
}
