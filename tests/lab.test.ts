import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,mkdir,symlink} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {resolve} from 'node:path';
import {Ledger,imagePath,externalDirectory} from '../evals/lab/store.ts';
import {DatasetSchema} from '../evals/lab/config.ts';
import {blindReport,pairs,metrics} from '../evals/lab/reviews.ts';
import type {Attempt} from '../evals/lab/runner.ts';
test('ledger enforces independent split limits, persists unknown spend, and prevents duplicate reservations',async()=>{
 const dir=await mkdtemp(resolve(tmpdir(),'lab-budget-'));const ledger=new Ledger(resolve(dir,'ledger.json'));await ledger.load();await ledger.reserve('one','development',9e6);await ledger.settle('one',null);await assert.rejects(ledger.reserve('two','development',2e6));await ledger.reserve('two','heldout',15e6);await assert.rejects(ledger.reserve('three','heldout',1));await assert.rejects(ledger.reserve('one','development',0));const resumed=new Ledger(ledger.path);await resumed.load();assert.equal(resumed.spent('development'),9e6);assert.equal(resumed.spent('heldout'),15e6);
});
test('known usage frees only unused reservation; cost-bound violation stops further spending',async()=>{
 const dir=await mkdtemp(resolve(tmpdir(),'lab-budget-'));const l=new Ledger(resolve(dir,'ledger.json'));await l.reserve('a','development',8e6);await l.settle('a',1e6);await l.reserve('b','development',2e6);await l.settle('b',3e6);assert.equal(l.blocked,true);await assert.rejects(l.reserve('c','heldout',1));
});
test('dataset preserves group splits and unique IDs',()=>{
 const c={id:'a',group:'outfit',split:'development',image:'a.jpg',rights:'Owned adult photo',metadata:{schemaVersion:1}};
 assert.throws(()=>DatasetSchema.parse({schemaVersion:1,cases:[c,{...c,id:'b',split:'heldout'}]}));assert.throws(()=>DatasetSchema.parse({schemaVersion:1,cases:[c,c]}));assert.ok(DatasetSchema.parse({schemaVersion:1,cases:[c]}));
});
test('external photos cannot escape through traversal or symlinks; data cannot enter Git',async()=>{
 const dir=await mkdtemp(resolve(tmpdir(),'lab-path-'));await mkdir(resolve(dir,'photos'));await writeFile(resolve(dir,'outside.jpg'),'x');await symlink(resolve(dir,'outside.jpg'),resolve(dir,'photos/link.jpg'));await assert.rejects(imagePath(resolve(dir,'photos'),'../outside.jpg'));await assert.rejects(imagePath(resolve(dir,'photos'),'link.jpg'));await mkdir(resolve(dir,'.git'));await assert.rejects(externalDirectory(resolve(dir,'data')));
});
const attempt=(id:string,experiment:string)=>({id,caseId:'case',group:'group',split:'development',imageHash:'same',experiment:{id:experiment},state:'complete',live:false,rounds:[],events:[],latencyMs:1,costMicrodollars:0,result:{kind:'report',report:{summary:'Advice',versions:{model:'secret-model'},runId:'secret-run',suggestions:[],criteria:[],strengths:[],limitations:[]}}}) as unknown as Attempt;
test('blind reports omit model and run identity; matching pairs are reproducible',()=>{
 const a=attempt('a','one'),b=attempt('b','two');assert.ok(!JSON.stringify(blindReport(a,'final')).includes('secret'));assert.deepEqual(pairs([a,b],'one','two','reports'),pairs([a,b],'one','two','reports'));assert.equal(pairs([a,{...b,imageHash:'different'}],'one','two','reports').length,0);assert.equal(pairs([a,b],'one','one','reports').length,0);
});
test('unlabelled metrics remain unknown and preference attribution follows blind mapping',()=>{
 const a=attempt('a','one'),b=attempt('b','two');const p=pairs([a,b],'one','two','reports')[0];const m=metrics([a,b],[],[{pair:p.id,choice:'A',reasons:'Useful',mapping:p}]);assert.equal(m[0].usefulActionCoverage,null);assert.equal(m.find(m=>m.experiment===(p.A.attempt==='a'?'one':'two'))?.preference.wins,1);
});
import {LabRunner} from '../evals/lab/runner.ts';
import {ExperimentSchema} from '../evals/lab/config.ts';
import {grayJpeg} from '../evals/lab/fixture.ts';
test('mock lab checkpoints, resumes without duplicate spend, reuses exact pools, and freezes dataset',async()=>{
 const root=await mkdtemp(resolve(tmpdir(),'lab-run-'));const photos=resolve(root,'photos');await mkdir(photos);await writeFile(resolve(photos,'test.jpg'),grayJpeg());
 const dataset=DatasetSchema.parse({schemaVersion:1,mockOnly:true,cases:[{id:'case',group:'outfit',split:'development',image:'test.jpg',rights:'Generated test fixture',metadata:{schemaVersion:1}}]});
 const settings={model:'google/gemini-3.1-flash-lite',route:'google-vertex/global',maxOutputTokens:3600,temperature:1,reasoningEffort:'low'};
 const config=ExperimentSchema.parse({id:'generator',split:'development',pipeline:'generator',generator:settings,evidence:settings,styling:settings,seed:'test'});
 const runner=new LabRunner(root,photos,dataset);await runner.init();await runner.run(config);await runner.run(config);let attempts=await runner.attempts();assert.equal(attempts.length,1);assert.equal(attempts[0].state,'complete');assert.equal(attempts[0].calls.length,1);assert.equal(attempts[0].costMicrodollars,0);
 await runner.run({...config,id:'review',pipeline:'review',sourceExperiment:'generator'});attempts=await runner.attempts();const review=attempts.find(a=>a.experiment.id==='review')!;assert.equal(review.calls.length,2);assert.equal(review.rounds.length,1);assert.deepEqual(review.rounds[0].assessment,attempts.find(a=>a.experiment.id==='generator')?.assessment);assert.ok(review.promptSnapshots.generator);assert.equal(review.result.kind,'report');
 await assert.rejects(new LabRunner(root,photos,{...dataset,cases:[]}).init(),/Dataset changed/);await assert.rejects(new LabRunner(root,photos,dataset,true).init(),/Mock fixture/);
});
