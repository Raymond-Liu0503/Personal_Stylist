import {createServer} from 'node:http';
import {readFile,unlink} from 'node:fs/promises';
import {resolve} from 'node:path';
import {z} from 'zod';
import {DatasetSchema,ExperimentSchema,PreferenceSchema,LabelSchema,models} from './config.ts';
import {externalDirectory,readJSON,atomic,lock,imagePath} from './store.ts';
import {LabRunner} from './runner.ts';
import {pairs,blindReport,metrics,type Pair} from './reviews.ts';
import {sanitizeJpeg} from '../../supabase/functions/_shared/security/input.ts';
const [dataPath,photoPath]=process.argv.slice(2);
if(!dataPath||!photoPath)throw new Error('Usage: npm run lab -- /external/lab-data /external/photos');
const root=await externalDirectory(dataPath),photos=await externalDirectory(photoPath);
const dataset=DatasetSchema.parse(await readJSON(resolve(root,'dataset.json')));
const fd=await lock(root);const runner=new LabRunner(root,photos,dataset,process.env.EVAL_LIVE==='true');await runner.init().catch(async error=>{await fd.close();await unlink(resolve(root,'lab.lock'));throw error;});
const port=Number(process.env.LAB_PORT??8787);if(!Number.isInteger(port)||port<1024||port>65535)throw new Error('Invalid LAB_PORT');
const origin=`http://127.0.0.1:${port}`;
type Vote=z.infer<typeof PreferenceSchema>&{mapping:Pair};
const load=async<T>(name:string):Promise<T[]>=>{try{return await readJSON<T[]>(resolve(root,name));}catch(e){if((e as NodeJS.ErrnoException).code!=='ENOENT')throw e;return [];}};
let votes=await load<Vote>('preferences.json'),labels=await load<z.infer<typeof LabelSchema>>('labels.json'),pairRecords=await load<Pair>('pairs.json');
let running:Promise<void>|undefined;let lastError:string|null=null;let mutations=Promise.resolve();
const server=createServer(async(req,res)=>{
 res.setHeader('Cache-Control','no-store');res.setHeader('X-Content-Type-Options','nosniff');res.setHeader('Content-Security-Policy',"default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; frame-ancestors 'none'");
 const json=(data:unknown,status=200)=>{res.writeHead(status,{'Content-Type':'application/json'});res.end(JSON.stringify(data));};
 try{
  if(req.headers.host!==`127.0.0.1:${port}`||req.headers.origin&&req.headers.origin!==origin)throw new Error('Invalid local origin');
  const url=new URL(req.url??'/',origin);
  if(req.method==='GET'){
   if(url.pathname==='/'){res.setHeader('Content-Type','text/html');res.end(await readFile(new URL('./index.html',import.meta.url)));return;}
   if(['/app.js','/style.css'].includes(url.pathname)){res.setHeader('Content-Type',url.pathname.endsWith('.js')?'text/javascript':'text/css');res.end(await readFile(new URL(`.${url.pathname}`,import.meta.url)));return;}
   if(url.pathname==='/api/state'){json({live:runner.live,active:!!runner.active,lastError,models,cases:dataset.cases.map(({image:_image,rights:_rights,...c})=>c),attempts:(await runner.attempts()).map(a=>({id:a.id,caseId:a.caseId,experiment:a.experiment.id,state:a.state,events:a.events})),budget:{development:runner.ledger.spent('development'),heldout:runner.ledger.spent('heldout'),blocked:runner.ledger.blocked}});return;}
   if(url.pathname==='/api/photo'){const c=dataset.cases.find(c=>c.id===url.searchParams.get('case'));if(!c)throw new Error('Unknown case');const bytes=sanitizeJpeg(new Uint8Array(await readFile(await imagePath(photos,c.image)))).bytes;res.setHeader('Content-Type','image/jpeg');res.end(bytes);return;}
   if(url.pathname==='/api/inspect'){const a=(await runner.attempts()).find(a=>a.id===url.searchParams.get('attempt'));if(!a)throw new Error('Unknown attempt');json({attempt:a,labels:labels.filter(l=>l.attempt===a.id)});return;}
   if(url.pathname==='/api/results'){json({metrics:metrics(await runner.attempts(),labels,votes),preferences:votes,labels,budget:runner.ledger.entries,notice:'Exploratory pilot: one reviewer and correlated outfit groups. Counts are descriptive, not proof of universal quality. Useful-action coverage is dual-critic retention among human-labelled useful candidates, not a full-photo recall estimate. Unlabelled actions are unknown.'});return;}
   if(url.pathname==='/api/pair'){const pair=pairRecords.find(p=>p.id===url.searchParams.get('id'));if(!pair)throw new Error('Unknown comparison');const attempts=await runner.attempts();json({id:pair.id,caseId:pair.caseId,brief:dataset.cases.find(c=>c.id===pair.caseId)?.metadata,A:blindReport(attempts.find(a=>a.id===pair.A.attempt)!,pair.A.variant),B:blindReport(attempts.find(a=>a.id===pair.B.attempt)!,pair.B.variant),reviewed:votes.some(v=>v.pair===pair.id)});return;}
  }
  if(req.method!=='POST'||req.headers.origin!==origin||req.headers['content-type']!=='application/json')throw new Error('Expected same-origin JSON request');
  let bytes=0;const chunks:Buffer[]=[];for await(const chunk of req){bytes+=chunk.length;if(bytes>32768)throw new Error('Request too large');chunks.push(chunk);}const data=JSON.parse(Buffer.concat(chunks).toString());
  const task=mutations.then(async()=>{
   if(url.pathname==='/api/run'){const config=ExperimentSchema.parse(data);if(runner.active)throw new Error('Experiment already running');lastError=null;running=runner.run(config).catch(e=>{lastError=e instanceof Error?e.message:'Experiment failed';});json({started:true});return;}
   if(url.pathname==='/api/cancel'){runner.active?.abort();json({cancelled:true});return;}
   if(url.pathname==='/api/pairs'){const x=z.object({left:z.string(),right:z.string(),kind:z.enum(['reports','repair'])}).strict().parse(data);const generated=pairs(await runner.attempts(),x.left,x.right,x.kind);pairRecords=[...pairRecords.filter(p=>!generated.some(g=>g.id===p.id)),...generated];await atomic(resolve(root,'pairs.json'),pairRecords);json(generated.map(p=>({id:p.id,caseId:p.caseId})));return;}
   if(url.pathname==='/api/preference'){const v=PreferenceSchema.parse(data);const mapping=pairRecords.find(p=>p.id===v.pair);if(!mapping)throw new Error('Unknown comparison');votes=[...votes.filter(x=>x.pair!==v.pair),{...v,mapping}];await atomic(resolve(root,'preferences.json'),votes);json({saved:true});return;}
   if(url.pathname==='/api/label'){const v=LabelSchema.parse(data);const attempt=(await runner.attempts()).find(a=>a.id===v.attempt);if(!attempt?.rounds[v.round]?.candidates.some(c=>c.id===v.candidate&&c.revision===v.revision))throw new Error('Unknown candidate revision');labels=[...labels.filter(x=>!(x.attempt===v.attempt&&x.round===v.round&&x.candidate===v.candidate&&x.revision===v.revision)),v];await atomic(resolve(root,'labels.json'),labels);json({saved:true});return;}
   throw new Error('Unknown route');
  });mutations=task.catch(()=>{});await task;
 }catch(e){if(!res.headersSent)json({error:e instanceof Error?e.message:'Lab request failed'},400);else res.end();}
});
server.on('error',async error=>{await fd.close();await unlink(resolve(root,'lab.lock'));console.error(error.message);process.exitCode=1;});
server.listen(port,'127.0.0.1',()=>console.log(`Evaluation lab: ${origin} (${runner.live?'LIVE, $25 ceiling':'mock, no inference'})`));
const shutdown=()=>{runner.active?.abort();server.close(async()=>{await running;await fd.close();await unlink(resolve(root,'lab.lock'));});};
process.on('SIGINT',shutdown);process.on('SIGTERM',shutdown);
