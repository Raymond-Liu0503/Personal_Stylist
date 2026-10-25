import {test} from 'node:test';
import assert from 'node:assert/strict';
import {configuredProvider,providerConfig,REQUIRED_PARAMETERS} from '../supabase/functions/_shared/providers/config.ts';
import {productionModel} from '../supabase/functions/_shared/agents/model-config.ts';

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
test('model changes revalidate the route and reach the actual generation request',async()=>{
 const checks:string[]=[];
 let checkedModel='';
 const fetcher:typeof fetch=async(url,init)=>{
  const path=String(url);
  if(path.endsWith('/chat/completions')){
   assert.equal(JSON.parse(String(init?.body)).model,checkedModel);
   return Response.json({choices:[{message:{content:'{}'}}],usage:{cost:0}});
  }
  if(path.includes('/models/')){
   checkedModel=path.split('/models/')[1].replace('/endpoints','');checks.push(checkedModel);
   return Response.json({data:{id:checkedModel,architecture:{input_modalities:['image']},endpoints:[{tag:'google-vertex/global',model_id:checkedModel,status:0,max_completion_tokens:65536,supported_parameters:REQUIRED_PARAMETERS}]}});
  }
  if(path.endsWith('/endpoints/zdr'))return Response.json({data:[productionModel.id,pro].map(model_id=>({tag:'google-vertex/global',model_id}))});
  return Response.json({data:{limit_remaining:10}});
 };
 for(const model of [productionModel.id,pro]){
  const provider=await configuredProvider(envFor(model),AbortSignal.timeout(1000),fetcher);
  assert.equal(provider.model,model);
  await provider.generate({messages:[],tools:[],schema:{},signal:AbortSignal.timeout(1000),maxOutputTokens:3600,temperature:1,reasoningEffort:'low'});
 }
 assert.deepEqual(checks,[productionModel.id,pro]);
});
