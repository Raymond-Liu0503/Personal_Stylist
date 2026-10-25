import {readFile,writeFile} from 'node:fs/promises';
import {resolve,relative} from 'node:path';
import {parseModelOutput} from '../../supabase/functions/_shared/agents/model-schema.ts';
import type {Provider} from '../../supabase/functions/_shared/providers/types.ts';
import {MetadataSchema} from '../../packages/contracts/src/index.ts';
import {MockProvider} from '../../supabase/functions/_shared/providers/mock.ts';
import {OpenRouterProvider} from '../../supabase/functions/_shared/providers/openrouter.ts';
import {runOutfit} from '../../supabase/functions/_shared/agents/runtime.ts';
import {comparisonModels,productionModel,type ComparisonModel} from '../../supabase/functions/_shared/agents/model-config.ts';
import type {ReasoningEffort} from '../../supabase/functions/_shared/providers/types.ts';
import {sanitizeJpeg} from '../../supabase/functions/_shared/security/input.ts';
const [manifestPath,imageRoot,outputPath]=process.argv.slice(2);
if(!manifestPath||!imageRoot||!outputPath)throw new Error('Usage: node --import tsx evals/runner/run.ts MANIFEST IMAGE_ROOT OUTPUT');
const live=process.env.EVAL_LIVE==='true';
if(live&&(process.env.OPENROUTER_CONFIG_APPROVED!=='true'||process.env.EVAL_RIGHTS_CONFIRMED!=='true'))throw new Error('Live evaluation requires provider approval and image-rights confirmation');
const repetitions=Number(process.env.EVAL_REPETITIONS??3);
if(!Number.isInteger(repetitions)||repetitions<1||repetitions>10)throw new Error('EVAL_REPETITIONS must be 1–10');
const model=(process.env.EVAL_MODEL??productionModel.id) as ComparisonModel;
if(!comparisonModels.includes(model))throw new Error('EVAL_MODEL is not an approved comparison model');
const temperature=Number(process.env.EVAL_TEMPERATURE??productionModel.temperature);
if(!Number.isFinite(temperature)||temperature<0||temperature>2)throw new Error('EVAL_TEMPERATURE must be 0–2');
const reasoningEffort=(process.env.EVAL_REASONING??productionModel.reasoning) as ReasoningEffort;
if(!['minimal','low','medium','high'].includes(reasoningEffort))throw new Error('EVAL_REASONING is invalid');
const evaluationLabel=process.env.EVAL_LABEL??'revised';
const manifest=JSON.parse(await readFile(manifestPath,'utf8'));const results=[];
const histories=Array.from({length:repetitions},()=>new Map<string,string[][]>());
for(const c of manifest.cases){
 if(typeof c.rights!=='string'||c.rights.includes('REPLACE'))throw new Error('Supply actual image rights records');
 const path=resolve(imageRoot,c.image);if(relative(resolve(imageRoot),path).startsWith('..'))throw new Error('Image path must remain under the external image root');
 const image=sanitizeJpeg(new Uint8Array(await readFile(path))).bytes;
 const provider=live?new OpenRouterProvider(process.env.OPENROUTER_API_KEY??'',(process.env.OPENROUTER_PROVIDERS??'').split(',').filter(Boolean),fetch,model):new MockProvider();
 for(let repeat=1;repeat<=repetitions;repeat++){
 const sequenceGroup=typeof c.sequenceGroup==='string'?c.sequenceGroup:null;
 const history=sequenceGroup?histories[repeat-1].get(sequenceGroup)??[]:[];
 const recentTechniques=history.slice(-3).flat();
 const providerOutputs:unknown[]=[];const diagnostics:unknown[]=[];
 const observed:Provider={model:provider.model,generate:async request=>{const response=await provider.generate(request);providerOutputs.push(response.output);return response;}};
 let costMicrodollars:number|null=0;const start=performance.now();
 const result=await runOutfit(observed,{runId:crypto.randomUUID(),metadata:MetadataSchema.parse(c.metadata),image,signal:AbortSignal.timeout(45000),recentTechniques,generationConfig:{maxOutputTokens:productionModel.maxOutputTokens,temperature,reasoningEffort}},u=>{costMicrodollars=costMicrodollars===null||u.costMicrodollars===null?null:costMicrodollars+u.costMicrodollars;},d=>diagnostics.push(d));
 if(sequenceGroup&&result.kind==='report'){history.push(result.techniqueCodes);histories[repeat-1].set(sequenceGroup,history);}
 let internal:ReturnType<typeof parseModelOutput>|null=null;try{internal=parseModelOutput(providerOutputs.at(-1));}catch{/* Raw output remains available for consented external review. */}
 results.push({id:c.id,repeat,sequenceGroup,recentTechniques,live,evaluationLabel,settings:{model:provider.model,temperature,reasoningEffort,maxOutputTokens:productionModel.maxOutputTokens},generated:internal?.kind==='report'?{diagnoses:internal.diagnoses,candidates:internal.suggestions}:null,providerOutputs,diagnostics,suggestionFamilies:internal?.kind==='report'?internal.suggestions.filter((s,i,a)=>a.findIndex(x=>x.action===s.action)===i).map(s=>s.family):[],latencyMs:Math.round(performance.now()-start),costMicrodollars,result});
 }
}
// Evaluations use consented test fixtures only. Output is outside git and contains reviewable prose.
await writeFile(outputPath,JSON.stringify({configuration:{evaluationLabel,model,temperature,reasoningEffort,maxOutputTokens:productionModel.maxOutputTokens},cases:results},null,2));
