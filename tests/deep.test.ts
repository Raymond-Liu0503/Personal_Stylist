import {test} from 'node:test';
import assert from 'node:assert/strict';
import {runDeep,validateReview,shuffled,validationIssues,type DeepEvent,type Candidate} from '../supabase/functions/_shared/agents/deep.ts';
import {mockReport} from '../supabase/functions/_shared/providers/mock.ts';
import {parseModelOutput} from '../supabase/functions/_shared/agents/model-schema.ts';
import type {Provider} from '../supabase/functions/_shared/providers/types.ts';
const input=()=>({runId:crypto.randomUUID(),metadata:{schemaVersion:1 as const},image:new Uint8Array([1]),signal:new AbortController().signal,seed:'test',generationConfig:{maxOutputTokens:3600,temperature:1,reasoningEffort:'low' as const}});
const usage={inputTokens:1,outputTokens:1,costMicrodollars:1};
function generator(outputs:unknown[]=[mockReport()]):Provider{return {model:'mock/generator',generate:async request=>{let output=outputs.shift();if(output instanceof Error)throw output;if((request.schema as any).properties?.candidateIds)output={assessment:output,candidateIds:(output as any)?.suggestions?.map((_:unknown,i:number)=>`c${i+1}`)??[]};return {output,usage};}};}
function critic(verdict='pass',options:{invalid?:boolean;badAssessment?:boolean;missed?:boolean;revision?:number;throw?:boolean;inspect?:(data:any)=>void}={}):Provider{return {model:'mock/critic',generate:async request=>{
 if(options.throw)throw Error('outage');const data=JSON.parse(request.messages[1].content as string);options.inspect?.(data);
 return {usage,output:{verdicts:options.invalid?[]:data.candidates.map((c:Candidate)=>({id:c.id,revision:options.revision??c.revision,verdict,evidence:'Visible clothing',reason:'Useful specific adjustment'})),assessmentValid:!options.badAssessment,assessmentIssues:options.badAssessment?['Invented hidden shoes']:[],missedOpportunity:options.missed?'Check hem balance':null}};
}};}
const pair=(a:Provider,b=a)=>({evidence:a,styling:b});
test('shared deadline aborts delayed inference without launching reviews',async()=>{
 let calls=0;
 const delayed:Provider={model:'delayed',generate:async r=>{calls++;await new Promise((_,reject)=>r.signal.addEventListener('abort',()=>reject(r.signal.reason),{once:true}));throw Error('unreachable');}};
 const timer=setTimeout(()=>{},100);
 try{await assert.rejects(runDeep(delayed,pair(delayed),{...input(),signal:AbortSignal.timeout(10)}));assert.equal(calls,1);}finally{clearTimeout(timer);}
});
test('invalid Deep generation returns a validation error instead of INTERNAL',async()=>{
 const events:string[]=[];
 await assert.rejects(runDeep(generator([{}]),pair(critic()),input(),()=>{},e=>events.push(e.stage)),{code:'INVALID_MODEL_OUTPUT'});
 assert.ok(events.includes('invalid_generation'));
});
test('invalid generation diagnostics identify schema fields without logging model text',async()=>{
 const report=mockReport();
 const secret='PRIVATE MODEL CONTENT';
 (report.criteria[0] as any).score=secret;
 const events:DeepEvent[]=[];let reviews=0;
 const reviewer:Provider={model:'unused',generate:async()=>{reviews++;throw Error('must not review invalid assessment');}};
 await assert.rejects(runDeep(generator([report]),pair(reviewer),input(),()=>{},e=>events.push(e)),{code:'INVALID_MODEL_OUTPUT'});
 const event=events.find(e=>e.stage==='invalid_generation');
 assert.deepEqual(event?.issues,[{code:'invalid_type',path:['criteria',0,'score']}]);
 assert.equal(JSON.stringify(events).includes(secret),false);
 assert.equal(reviews,0);
 assert.deepEqual(validationIssues(new Error(secret)),[]);
 assert.deepEqual(validationIssues({issues:[{code:'custom',path:[secret],message:secret}]}),[{code:'custom',path:['unknown']}]);
 assert.deepEqual(validationIssues({issues:[{code:secret,path:[]}]}),[]);
});
function blankCriterionReport(){const report=mockReport();report.criteria[4].observation='   ';return report;}
test('blank criterion text gets one fresh generation and dual review, with usage preserved',async()=>{
 const invalid=blankCriterionReport();invalid.summary='PRIVATE INVALID OUTPUT';
 const outputs=[invalid,mockReport()];let generations=0;let usages=0;
 const p:Provider={model:'generator',generate:async request=>{
  generations++;
  assert.match(String(request.messages[0].content),/nonblank observation and explanation/);
  assert.equal(JSON.stringify(request.messages).includes('PRIVATE INVALID OUTPUT'),false);
  if(generations===2)assert.match(String(request.messages[1].content),/validationIssues/);
  return {output:outputs.shift(),usage};
 }};
 const events:DeepEvent[]=[];
 const out=await runDeep(p,pair(critic()),input(),()=>usages++,e=>events.push(e));
 assert.equal(out.result.kind,'report');assert.equal(out.calls,4);assert.equal(usages,4);
 assert.equal(out.rounds.length,1);assert.equal(Object.keys(out.rounds[0].reviews).length,2);
 assert.equal(events.filter(e=>e.stage==='generation_retry').length,1);
});
test('repeated blank criterion text stops after two generations without critic calls',async()=>{
 let calls=0;
 const p:Provider={model:'blank',generate:async()=>{calls++;return {output:blankCriterionReport(),usage};}};
 await assert.rejects(runDeep(p,pair(p),input()),{code:'INVALID_MODEL_OUTPUT'});
 assert.equal(calls,2);
});
test('blank text recovery respects disabled repair and remaining deadline',async()=>{
 for(const options of [{repair:false},{deadlineAt:Date.now()+1000}]){
  let calls=0;const p:Provider={model:'blank',generate:async()=>{calls++;return {output:blankCriterionReport(),usage};}};
  await assert.rejects(runDeep(p,pair(p),{...input(),...options}),{code:'INVALID_MODEL_OUTPUT'});
  assert.equal(calls,1);
 }
});
test('generation recovery never starts a revision that would exceed the six-call budget',async()=>{
 const out=await runDeep(generator([blankCriterionReport(),mockReport()]),pair(critic('pass',{missed:true})),input());
 assert.equal(out.result.kind,'report');assert.equal(out.calls,4);
 const rejected=await runDeep(generator([blankCriterionReport(),mockReport()]),pair(critic('pass',{badAssessment:true})),input());
 assert.equal(rejected.result.kind,'unvalidated');assert.equal(rejected.calls,4);
});
test('provider failure during blank text recovery is not retried or hidden',async()=>{
 const failure=new Error('provider unavailable');
 await assert.rejects(runDeep(generator([blankCriterionReport(),failure]),pair(critic()),input()),error=>error===failure);
});
test('cancellation before corrective generation prevents another provider call',async()=>{
 const controller=new AbortController();let calls=0;
 const p:Provider={model:'blank',generate:async()=>{calls++;return {output:blankCriterionReport(),usage};}};
 await assert.rejects(runDeep(p,pair(p),{...input(),signal:controller.signal},()=>{},e=>{if(e.stage==='generation_retry')controller.abort();}),{name:'AbortError'});
 assert.equal(calls,1);
});
test('Deep discards malformed optional candidates before critic review',async()=>{
 const report=mockReport();
 report.suggestions.push({...report.suggestions[0],technique:'invalid-technique'} as any);
 const events:{stage:string;rejectedCount?:number}[]=[];
 const out=await runDeep(generator([report]),pair(critic()),input(),()=>{},e=>events.push(e));
 assert.equal(out.result.kind,'report');
 assert.equal(out.calls,3);
 assert.ok(events.some(e=>e.stage==='candidates'&&e.rejectedCount===1));
});
test('near deadline skips optional repair and keeps approved original assessment',async()=>{
 const out=await runDeep(generator(),pair(critic('pass',{missed:true})),{...input(),deadlineAt:Date.now()+1000});
 assert.equal(out.calls,3);assert.equal(out.result.kind,'report');
});
test('two whole-set critics run concurrently; identity and impact are hidden',async()=>{
 let starts=0;let release!:()=>void;const barrier=new Promise<void>(r=>release=r);
 const inner=critic('pass',{inspect:data=>{assert.equal(data.candidates[0].action.impact,undefined);assert.equal(data.model,undefined);assert.ok(data.assessment.criteria);}});
 const p:Provider={model:'critic',generate:async r=>{assert.deepEqual(r.image,new Uint8Array([1]));if(++starts===2)release();await barrier;return inner.generate(r);}};
 const out=await runDeep(generator(),pair(p),input());assert.equal(out.calls,3);assert.equal(out.result.kind,'report');if(out.result.kind==='report')assert.equal(out.result.report.suggestions.length,1);
});
test('rejects duplicate, missing, unknown and stale verdicts',()=>{
 const raw=parseModelOutput(mockReport());assert.equal(raw.kind,'report');if(raw.kind!=='report')return;
 const cs=raw.suggestions.map((action,i)=>({id:`c${i+1}`,revision:2,action}));
 for(const verdicts of [[],[{id:'c1',revision:1,verdict:'pass',evidence:'x',reason:'x'}],[{id:'unknown',revision:2,verdict:'pass',evidence:'x',reason:'x'}]])assert.throws(()=>validateReview({verdicts,assessmentValid:true,assessmentIssues:[],missedOpportunity:null},cs));
});
function contradictoryCritic():Provider {
 return {model:'contradictory',generate:async request=>{
  const response=await critic('pass',{badAssessment:true}).generate(request);
  return {...response,output:{...(response.output as object),assessmentValid:true}};
 }};
}
test('contradictory critic assessment never approves an unrepaired report',async()=>{
 const out=await runDeep(generator(),pair(critic(),contradictoryCritic()),{...input(),repair:false});
 assert.equal(out.result.kind,'unvalidated');
 assert.equal(out.rounds[0].reviews.styling?.assessmentValid,false);
 assert.deepEqual(out.rounds[0].reviews.styling?.assessmentIssues,['Invented hidden shoes']);
 assert.deepEqual(out.rounds[0].errors,[]);
});
test('contradictory critic feedback permits only bounded repair and fresh dual review',async()=>{
 let n=0;
 const reviewer:Provider={model:'reviewer',generate:async request=>(++n<=2?contradictoryCritic():critic()).generate(request)};
 const out=await runDeep(generator([mockReport(),mockReport()]),pair(reviewer),input());
 assert.equal(out.result.kind,'report');assert.equal(out.calls,6);
 assert.equal(out.rounds[1].candidates[0].revision,2);
});
test('contradictory assessment remains unpublished when repair fails or time is short',async()=>{
 for(const options of [{},{deadlineAt:Date.now()+1000}]){
  const out=await runDeep(generator([mockReport(),new Error('repair unavailable')]),pair(contradictoryCritic()),{...input(),...options});
  assert.equal(out.result.kind,'unvalidated');assert.ok(out.calls<=4);
 }
});
test('critic disagreement publishes zero, never fills slots',async()=>{
 const out=await runDeep(generator(),pair(critic(),critic('reject')),{...input(),repair:false});assert.equal(out.result.kind,'report');if(out.result.kind==='report'){assert.equal(out.result.report.suggestions.length,0);assert.match(out.result.report.limitations.join(' '),/could not be validated/);}
});
test('critic outage cannot masquerade as success or a photo retake',async()=>{
 const out=await runDeep(generator(),pair(critic(),critic('pass',{throw:true})),input());assert.equal(out.calls,3);assert.equal(out.result.kind,'unvalidated');
});
test('one repair and two exact-revision rechecks, maximum six calls',async()=>{
 let n=0;const c:Provider={model:'critic',generate:async request=>critic(++n<=2?'revise':'pass').generate(request)};
 const out=await runDeep(generator([mockReport(),mockReport()]),pair(c),input());assert.equal(out.calls,6);assert.equal(out.rounds.length,2);assert.equal(out.rounds[1].candidates[0].revision,2);assert.equal(out.result.kind,'report');
});
test('repair discards malformed optional candidates without shifting reordered or new IDs',async()=>{
 const initial=mockReport();
 initial.suggestions=[1,2,3].map(i=>({...initial.suggestions[0],action:`Original action ${i}`}));
 const revised=mockReport();
 revised.suggestions=[
  {...initial.suggestions[1],technique:'invalid-technique'},
  {...initial.suggestions[2],action:'Repaired third action'},
  {...initial.suggestions[0],action:'New action'},
  {...initial.suggestions[0],action:'Repaired first action'},
 ] as any;
 let generations=0;let reviews=0;const events:DeepEvent[]=[];
 const p:Provider={model:'generator',generate:async()=>({usage,output:++generations===1?initial:{assessment:revised,candidateIds:['c2','c3','n1','c1']}})};
 const reviewer:Provider={model:'critic',generate:async request=>critic('pass',{badAssessment:++reviews<=2}).generate(request)};
 const out=await runDeep(p,pair(reviewer),input(),()=>{},e=>events.push(e));
 assert.equal(out.result.kind,'report');assert.equal(out.calls,6);
 assert.deepEqual(out.rounds[1].candidates.map(c=>[c.id,c.revision,c.action.action]),[
  ['c3',2,'Repaired third action'],['n1',2,'New action'],['c1',2,'Repaired first action'],
 ]);
 assert.ok(events.some(e=>e.stage==='candidates'&&e.revision===2&&e.rejectedCount===1));
});
test('repair rejects invalid identities before optional candidates can be dropped',async()=>{
 for(const candidateIds of [['c6','c1'],['c1','c1'],['c1']]){
  const revised=mockReport();revised.suggestions=[{...revised.suggestions[0],technique:'invalid-technique'},revised.suggestions[0]] as any;
  let generations=0;const events:DeepEvent[]=[];
  const p:Provider={model:'generator',generate:async()=>({usage,output:++generations===1?mockReport():{assessment:revised,candidateIds}})};
  const out=await runDeep(p,pair(critic('pass',{badAssessment:true})),input(),()=>{},e=>events.push(e));
  assert.equal(out.result.kind,'unvalidated');assert.equal(out.calls,4);
  assert.ok(events.some(e=>e.stage==='revision_error'&&e.phase==='identities'));
  assert.equal(events.some(e=>e.stage==='recheck'),false);
 }
});
test('repair required assessment fields remain strict and failures have safe diagnostics',async()=>{
 const events:DeepEvent[]=[];
 const out=await runDeep(generator([mockReport(),blankCriterionReport()]),pair(critic('pass',{badAssessment:true})),input(),()=>{},e=>events.push(e));
 assert.equal(out.result.kind,'unvalidated');assert.equal(out.calls,4);
 const failure=events.find(e=>e.stage==='revision_error');
 assert.equal(failure?.phase,'assessment');
 assert.deepEqual(failure?.issues,[{code:'too_small',path:['criteria',4,'observation']}]);
 assert.ok(events.some(e=>e.stage==='review_summary'&&e.assessmentValid===false&&e.assessmentIssueCount===1));
});
test('repair provider and envelope failures are distinguished without logging contents',async()=>{
 for(const [response,phase] of [[new Error('PRIVATE PROVIDER TEXT'),'provider'],[{},'envelope']] as const){
  let generations=0;const events:DeepEvent[]=[];
  const p:Provider={model:'generator',generate:async()=>{
   if(++generations===1)return {output:mockReport(),usage};
   if(response instanceof Error)throw response;
   return {output:response,usage};
  }};
  const out=await runDeep(p,pair(critic('pass',{badAssessment:true})),input(),()=>{},e=>events.push(e));
  assert.equal(out.result.kind,'unvalidated');
  assert.equal(events.find(e=>e.stage==='revision_error')?.phase,phase);
  assert.equal(JSON.stringify(events).includes('PRIVATE PROVIDER TEXT'),false);
 }
});
test('stale repair approvals cannot publish the repaired action',async()=>{
 const out=await runDeep(generator([mockReport(),mockReport()]),pair(critic('revise',{revision:1})),input());assert.equal(out.result.kind,'report');if(out.result.kind==='report')assert.equal(out.result.report.suggestions.length,0);
});
test('failed repair retains originally approved subset when assessment is sound',async()=>{
 const out=await runDeep(generator([mockReport(),new Error('repair down')]),pair(critic('pass',{missed:true})),input());assert.equal(out.result.kind,'report');if(out.result.kind==='report')assert.equal(out.result.report.suggestions.length,1);
});
test('material false observations block original report after failed repair',async()=>{
 const out=await runDeep(generator([mockReport(),new Error('repair down')]),pair(critic('pass',{badAssessment:true})),input());assert.equal(out.result.kind,'unvalidated');
});
test('repaired evidence is independently checked',async()=>{
 let n=0;const c:Provider={model:'critic',generate:async r=>critic('pass',{badAssessment:++n<=2}).generate(r)};
 const out=await runDeep(generator([mockReport(),mockReport()]),pair(c),input());assert.equal(out.result.kind,'report');assert.equal(out.calls,6);
});
test('empty validated candidate set is distinct from rejection',async()=>{
 const raw={...mockReport(),suggestions:[],diagnoses:[]};const out=await runDeep(generator([raw]),pair(critic()),input());assert.equal(out.calls,3);if(out.result.kind==='report')assert.match(out.result.report.limitations.join(' '),/No worthwhile change/);else assert.fail();
});
test('cancellation reaches both pending critics and aborts publication',async()=>{
 const controller=new AbortController();let count=0;const c:Provider={model:'critic',generate:async r=>new Promise((_,reject)=>{r.signal.addEventListener('abort',()=>reject(r.signal.reason),{once:true});if(++count===2)controller.abort();})};
 const out=await runDeep(generator(),pair(c),{...input(),signal:controller.signal});assert.equal(count,2);assert.equal(out.result.kind,'unvalidated');
});
test('malformed initial generation has no nested generation repair loop',async()=>{
 let calls=0;const p:Provider={model:'bad',generate:async()=>{calls++;return {output:{bad:true},usage};}};await assert.rejects(runDeep(p,pair(critic()),input()));assert.equal(calls,1);
});
test('candidate ordering is reproducible',()=>{assert.deepEqual(shuffled([1,2,3,4,5,6],'a'),shuffled([1,2,3,4,5,6],'a'));assert.notDeepEqual(shuffled([1,2,3,4,5,6],'a'),shuffled([1,2,3,4,5,6],'b'));});
import {signReceipt,verifyReceipt} from '../supabase/functions/_shared/security/receipts.ts';
test('reviewed report retains signed-save compatibility and hides critic explanations',async()=>{
 const out=await runDeep(generator(),pair(critic()),input());if(out.result.kind!=='report')return assert.fail();const secret='test-only-signing-secret-with-32-characters';const receipt=await signReceipt(secret,'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',out.result.report);await verifyReceipt(secret,'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',out.result.report,receipt);assert.equal('reviews' in out.result.report,false);
});
test('useful unconventional advice passes without an English keyword filter',async()=>{
 const raw=mockReport();raw.suggestions[0].action='Fold only the left cuff to echo the asymmetric layer.';const out=await runDeep(generator([raw]),pair(critic()),input());if(out.result.kind!=='report')return assert.fail();assert.match(out.result.report.suggestions[0].action,/left cuff/);
});
test('contradictory alternatives fail dual review instead of filling three slots',async()=>{
 const raw=mockReport();raw.suggestions.push({...raw.suggestions[0],action:'Keep both cuffs fully extended.'});const out=await runDeep(generator([raw]),pair(critic('reject')),{...input(),repair:false});if(out.result.kind!=='report')return assert.fail();assert.equal(out.result.report.suggestions.length,0);
});
test('a partial timeout cancels the pending critic and publishes no report',async()=>{
 const controller=new AbortController();let started!:()=>void;const ready=new Promise<void>(resolve=>started=resolve);
 const pending:Provider={model:'slow',generate:async r=>new Promise((_,reject)=>{r.signal.addEventListener('abort',()=>reject(r.signal.reason),{once:true});started();})};
 const resultPromise=runDeep(generator(),pair(critic(),pending),{...input(),signal:controller.signal});
 await ready; // both critics have started; the pending critic blocks on its abort listener
 controller.abort(new DOMException('Deadline exceeded','TimeoutError'));
 const out=await resultPromise;
 // The aborted critic's error is captured in round.errors; runDeep returns unvalidated
 if(out.result.kind!=='unvalidated')throw new Error(`Expected unvalidated, got ${out.result.kind}`);
});
