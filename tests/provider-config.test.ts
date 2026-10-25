import {test} from 'node:test';
import assert from 'node:assert/strict';
import {configuredProvider,providerConfig,REQUIRED_PARAMETERS,selectedProvider,validateRoute,requiredParameters} from '../supabase/functions/_shared/providers/config.ts';
import {analysisProfiles,productionModel} from '../supabase/functions/_shared/agents/model-config.ts';
import {assertReservation} from '../supabase/functions/_shared/providers/budget.ts';

const pro='google/gemini-3.1-pro-preview';
const envFor=(model:string,environment='local')=>{
 const values:Record<string,string>={APP_ENV:environment,AI_PROVIDER:'openrouter',OPENROUTER_API_KEY:'test-key',OPENROUTER_CONFIG_APPROVED:'true',OPENROUTER_PROVIDERS:'google-vertex/global',OPENROUTER_MODEL:model};
 return (name:string)=>values[name];
};
test('comparison model is allowed only locally and unknown models stay disabled',()=>{
 assert.equal(providerConfig(envFor(pro)).mode,'live');
 assert.equal(providerConfig(envFor(productionModel.id,'beta')).mode,'live');
 assert.throws(()=>providerConfig(envFor(pro,'beta')),{code:'DISABLED'});
 assert.throws(()=>providerConfig(envFor('unknown/model')),{code:'DISABLED'});
});
test('four immutable profile routes, token parameters and bounded reserves',()=>{
 assert.equal(analysisProfiles.length,4);
 for(const profile of analysisProfiles){assert.equal(Object.isFrozen(profile),true);assertReservation(profile);assert.deepEqual(profile.providers,[profile.stylistTier==='expert'?'google-vertex/global':'azure']);assert.ok(requiredParameters(profile).includes(profile.tokenParameter));assert.equal(profile.temperature,undefined);}
 assert.deepEqual(analysisProfiles.map(p=>p.reservation),[100000,250000,1200000,5000000]);
});
test('expert model routes are disabled server-side while Everyday remains selectable',async()=>{
 const profiles=analysisProfiles.filter(profile=>profile.stylistTier==='expert');
 for(const profile of profiles){
  await assert.rejects(selectedProvider(envFor(profile.model),AbortSignal.timeout(100),{stylistTier:'expert',analysisDepth:profile.analysisDepth}),{code:'DISABLED'});
 }
 assert.equal(analysisProfiles.filter(profile=>profile.stylistTier==='everyday').length,2);
});
test('live new profiles are closed until profile and input bound are enabled',async()=>{
 const env=envFor('openai/gpt-5.6-luna');
 await assert.rejects(selectedProvider(env,AbortSignal.timeout(100),{stylistTier:'everyday',analysisDepth:'quick'}),{code:'DISABLED'});
});
test('legacy route checks keep original strict required parameters',()=>{
 assert.ok(REQUIRED_PARAMETERS.includes('tools'));assert.ok(REQUIRED_PARAMETERS.includes('tool_choice'));
});
test('exact profile route, ZDR tag, price, input, token setting and effort are mandatory',()=>{
 const p=analysisProfiles[0];const data={data:{id:p.model,architecture:{input_modalities:['image']},endpoints:[{tag:'azure',model_id:p.model,status:0,max_completion_tokens:16384,supported_parameters:requiredParameters(p),pricing:{prompt:'0.0000002',completion:'0.0000012'}}]}};
 const zdr={data:[{tag:'azure',model_id:p.model}]};
 validateRoute(data,zdr,['azure'],p.model,p);
 assert.throws(()=>validateRoute(data,{data:[]},['azure'],p.model,p),{code:'DISABLED'});
 assert.throws(()=>validateRoute({...data,data:{...data.data,endpoints:[{...data.data.endpoints[0],tag:'google-vertex/global'}]}},zdr,['azure'],p.model,p),{code:'DISABLED'});
 assert.throws(()=>validateRoute({...data,data:{...data.data,endpoints:[{...data.data.endpoints[0],pricing:{prompt:'0.1',completion:'0.1'}}]}},zdr,['azure'],p.model,p),{code:'DISABLED'});
});
test('model changes revalidate the route and reach the actual generation request',async()=>{
 const checks:string[]=[];let checkedModel='';
 const fetcher:typeof fetch=async(url,init)=>{
  const path=String(url);
  if(path.endsWith('/chat/completions')){assert.equal(JSON.parse(String(init?.body)).model,checkedModel);return Response.json({choices:[{message:{content:'{}'}}],usage:{prompt_tokens:1,completion_tokens:1,cost:0}});}
  if(path.includes('/models/')){checkedModel=path.split('/models/')[1].replace('/endpoints','');checks.push(checkedModel);return Response.json({data:{id:checkedModel,architecture:{input_modalities:['image']},endpoints:[{tag:'google-vertex/global',model_id:checkedModel,status:0,max_completion_tokens:65536,supported_parameters:REQUIRED_PARAMETERS}]}});}
  if(path.endsWith('/endpoints/zdr'))return Response.json({data:[productionModel.id,pro].map(model_id=>({tag:'google-vertex/global',model_id}))});
  return Response.json({data:{limit_remaining:10}});
 };
 for(const model of [productionModel.id,pro]){const provider=await configuredProvider(envFor(model),AbortSignal.timeout(1000),fetcher);assert.equal(provider.model,model);await provider.generate({messages:[],tools:[],schema:{},signal:AbortSignal.timeout(1000),maxOutputTokens:3600,temperature:1,reasoningEffort:'low'});}
 assert.deepEqual(checks,[productionModel.id,pro]);
});
