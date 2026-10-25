import {readFile,mkdir,readdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {randomUUID} from 'node:crypto';
import {runDeep,finalizeAssessment,type Assessment,type ReviewRound} from '../../supabase/functions/_shared/agents/deep.ts';
import {runOutfit} from '../../supabase/functions/_shared/agents/runtime.ts';
import {parseModelOutput,outputJsonSchema} from '../../supabase/functions/_shared/agents/model-schema.ts';
import {outfit} from '../../supabase/functions/_shared/agents/registry.ts';
import {promptFor} from '../../packages/contracts/src/index.ts';
import {sanitizeJpeg} from '../../supabase/functions/_shared/security/input.ts';
import type {Provider,Usage} from '../../supabase/functions/_shared/providers/types.ts';
import {criticPrompts} from '../../supabase/functions/_shared/agents/deep.ts';
import {hash,atomic,readJSON,imagePath,Ledger} from './store.ts';
import {verifiedProvider} from './providers.ts';
import type {Dataset,Experiment} from './config.ts';
export type Attempt={id:string;key:string;caseId:string;group:string;split:Experiment['split'];experiment:Experiment;configHash:string;imageHash:string;live:boolean;state:'running'|'complete'|'failed';started:string;latencyMs:number;costMicrodollars:number|null;reservedMicrodollars:number;calls:{role:string;requestHash:string;state:string;usage?:Usage;output?:unknown}[];rounds:ReviewRound[];events:{stage:string;at:string}[];result?:any;assessment?:Assessment;error?:string;routes:unknown[];promptSnapshots:{generator:string;critic:{evidence:string;styling:string}};implementationHash:string};
export class LabRunner{
 readonly ledger:Ledger;
 active:AbortController|null=null;
 constructor(readonly root:string,readonly images:string,readonly dataset:Dataset,readonly live=false){this.ledger=new Ledger(resolve(root,'ledger.json'));}
 async init(){if(this.live&&this.dataset.mockOnly)throw new Error('Mock fixture cannot be used for live evaluation');
  const digest=hash(this.dataset);try{const frozen=await readJSON<{hash:string}>(resolve(this.root,'dataset-lock.json'));if(frozen.hash!==digest)throw new Error('Dataset changed; restore the pilot manifest');}catch(e){if((e as NodeJS.ErrnoException).code!=='ENOENT')throw e;await atomic(resolve(this.root,'dataset-lock.json'),{hash:digest});}
  await mkdir(resolve(this.root,'attempts'),{recursive:true,mode:0o700});await this.ledger.load();}
 async attempts(){return Promise.all((await readdir(resolve(this.root,'attempts'))).filter(n=>n.endsWith('.json')).sort().map(n=>readJSON<Attempt>(resolve(this.root,'attempts',n))));}
 async prompts(config:Experiment){
  const load=async(id:string,builtin:string,standard:string)=>id===builtin?standard:readFile(resolve(this.root,'prompts',`${id}.txt`),'utf8');
  const generator=await load(config.generatorPrompt,'outfit-v1',outfit.skillBundle.instructions);
  const critic=config.criticPrompt==='review-v1'?criticPrompts:{evidence:await load(config.criticPrompt,'', ''),styling:await load(config.criticPrompt,'','')};
  return {generator,critic};
 }
 async run(config:Experiment){
  if(this.active)throw new Error('An experiment is already running');const controller=new AbortController();this.active=controller;
  try{
   const prompts=await this.prompts(config);
   const codeFiles=['runner.ts','config.ts','providers.ts','store.ts','../../supabase/functions/_shared/agents/deep.ts','../../supabase/functions/_shared/agents/runtime.ts','../../supabase/functions/_shared/agents/model-schema.ts','../../supabase/functions/_shared/agents/scoring.ts','../../supabase/functions/_shared/agents/suggestions.ts','../../supabase/functions/_shared/providers/openrouter.ts','../../packages/contracts/src/index.ts'];
   const implementationHash=hash(await Promise.all(codeFiles.map(file=>readFile(new URL(file,import.meta.url),'utf8'))));
   const configHash=hash({config,prompts,implementationHash,live:this.live});
   const existing=await this.attempts();
   if(existing.some(a=>a.experiment.id===config.id&&a.configHash!==configHash))throw new Error('Experiment IDs are immutable: use a new ID for changed settings/prompts');
   for(const c of this.dataset.cases.filter(c=>c.split===config.split)){
    controller.signal.throwIfAborted();const image=sanitizeJpeg(new Uint8Array(await readFile(await imagePath(this.images,c.image)))).bytes;
    const imageHash=hash(image);const key=hash({configHash,case:c,imageHash});
    if(existing.some(a=>a.key===key))continue; // Failed/interrupted attempts are preserved, never silently rebilled.
    const source=config.sourceExperiment?existing.find(a=>a.experiment.id===config.sourceExperiment&&a.caseId===c.id&&a.state==='complete'):undefined;
    const initial=source?.rounds[config.sourceRound]?.assessment??(config.sourceRound===0?source?.assessment:undefined);
    if(config.sourceExperiment&&(!initial||source?.imageHash!==imageHash||hash(source.experiment.split)!==hash(config.split)))throw new Error('Source pool missing or image/split changed');
    const signal=AbortSignal.any([controller.signal,AbortSignal.timeout(config.pipeline==='deep'||config.pipeline==='review'?90000:45000)]);
    const review=config.pipeline==='review'||config.pipeline==='deep';
    const g=await verifiedProvider(config.generator,this.live,signal);
    const [e,s]=review?await Promise.all([verifiedProvider(config.evidence,this.live,signal),verifiedProvider(config.styling,this.live,signal)]):[g,g];
    const genCalls=config.pipeline==='baseline'?2:initial?0:1;
    const reserve=g.bound*(genCalls+(config.pipeline==='deep'?1:0))+(review?(e.bound+s.bound)*(config.pipeline==='deep'?2:1):0);
    const id=randomUUID();const attempt:Attempt={id,key,caseId:c.id,group:c.group,split:c.split,experiment:config,configHash,imageHash,live:this.live,state:'running',started:new Date().toISOString(),latencyMs:0,costMicrodollars:0,reservedMicrodollars:reserve,calls:[],rounds:[],events:[],routes:[g.snapshot,...(review?[e.snapshot,s.snapshot]:[])],promptSnapshots:prompts,implementationHash};
    const path=resolve(this.root,'attempts',`${id}.json`);const started=Date.now();
    // Serialize snapshots, including concurrent critic completions, and finish every checkpoint before settlement.
    let writes=Promise.resolve();const checkpoint=()=>{const snapshot=structuredClone(attempt);writes=writes.then(()=>atomic(path,snapshot));return writes;};
    await this.ledger.reserve(id,c.split,reserve);await checkpoint();
    const measured=(role:string,provider:Provider,settings:Experiment['generator']):Provider=>({model:provider.model,generate:async request=>{
      const record:Attempt['calls'][number]={role,requestHash:hash({...request,...settings,signal:undefined,image:imageHash}),state:'dispatched'};attempt.calls.push(record);await checkpoint();
      try{const response=await provider.generate({...request,...settings});record.state='complete';record.output=response.output;record.usage=response.usage;await checkpoint();return response;}
      catch(err){record.state='uncertain';await checkpoint();throw err;}
    }});
    const generator=measured('generator',g.provider,config.generator);
    const usage=(_u:Usage)=>{};
    const input={runId:randomUUID(),metadata:c.metadata,image,signal,recentTechniques:c.recentTechniques,generationConfig:config.generator,seed:config.seed,generatorPrompt:prompts.generator,criticPromptOverrides:prompts.critic,initialAssessment:initial,repair:config.pipeline==='deep'};
    try{
      if(review){const output=await runDeep(generator,{evidence:measured('evidence',e.provider,config.evidence),styling:measured('styling',s.provider,config.styling)},input,usage,event=>{attempt.events.push({...event,at:new Date().toISOString()});},round=>{attempt.rounds.push(round);});attempt.result=output.result;attempt.rounds=output.rounds;attempt.assessment=output.rounds[0]?.assessment;}
      else if(config.pipeline==='baseline'){
        if(config.generatorPrompt!=='outfit-v1')throw new Error('Baseline uses the existing frozen production prompt');
        attempt.result=await runOutfit(generator,input);
        const raw=parseModelOutput(attempt.calls.at(-1)?.output);if(raw.kind==='report')attempt.assessment=raw;
      }else{
        if(!initial)attempt.events.push({stage:'generation',at:new Date().toISOString()});
        const raw=initial??parseModelOutput((await generator.generate({messages:[{role:'system',content:prompts.generator},{role:'user',content:JSON.stringify({prompt:promptFor(c.metadata),context:c.metadata.context??{},recentTechniques:c.recentTechniques})}],image,tools:[],schema:outputJsonSchema,signal,...config.generator})).output);
        if(raw.kind==='report'){attempt.assessment=raw;attempt.result=finalizeAssessment(raw,raw.suggestions.map((action,i)=>({id:`c${i+1}`,revision:1,action})),input,generator.model);}else attempt.result=raw;
      }
      signal.throwIfAborted();attempt.state='complete';
    }catch{attempt.state='failed';attempt.error=signal.aborted?'Cancelled or deadline exceeded':'Provider or validation failure; inspect checkpointed calls';}
    finally{
      const known=attempt.calls.every(call=>call.state==='complete'&&call.usage?.costMicrodollars!==null&&call.usage?.costMicrodollars!==undefined);
      attempt.costMicrodollars=known?attempt.calls.reduce((n,c)=>n+(c.usage?.costMicrodollars??0),0):null;
      attempt.latencyMs=Date.now()-started;await checkpoint();await this.ledger.settle(id,attempt.costMicrodollars);
    }
   }
  }finally{this.active=null;}
 }
}
