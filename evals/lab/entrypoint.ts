// Headless entrypoint for reproducible experiments and future offline optimizer adapters.
import {resolve} from 'node:path';
import {unlink} from 'node:fs/promises';
import {DatasetSchema,ExperimentSchema} from './config.ts';
import {externalDirectory,readJSON,lock} from './store.ts';
import {LabRunner} from './runner.ts';
const [data,images,experiment]=process.argv.slice(2);
if(!data||!images||!experiment)throw new Error('Usage: npm run lab:run -- DATA_ROOT IMAGE_ROOT EXPERIMENT_JSON');
const root=await externalDirectory(data),photos=await externalDirectory(images);const fd=await lock(root);
try{const runner=new LabRunner(root,photos,DatasetSchema.parse(await readJSON(resolve(root,'dataset.json'))),process.env.EVAL_LIVE==='true');await runner.init();process.on('SIGINT',()=>runner.active?.abort());process.on('SIGTERM',()=>runner.active?.abort());await runner.run(ExperimentSchema.parse(await readJSON(experiment)));console.log(JSON.stringify({attempts:(await runner.attempts()).map(a=>({id:a.id,state:a.state})),spending:{development:runner.ledger.spent('development'),heldout:runner.ledger.spent('heldout')}}));}
finally{await fd.close();await unlink(resolve(root,'lab.lock'));}
