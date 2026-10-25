import {writeFile,mkdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {externalDirectory} from './store.ts';
import {grayJpeg} from './fixture.ts';
const path=process.argv[2];if(!path)throw new Error('Usage: npm run lab:demo -- /external/demo-directory');
const root=await externalDirectory(path);await mkdir(resolve(root,'photos'),{recursive:true,mode:0o700});
await writeFile(resolve(root,'photos','gray.jpg'),grayJpeg(),{mode:0o600,flag:'wx'});
await writeFile(resolve(root,'dataset.json'),JSON.stringify({schemaVersion:1,mockOnly:true,cases:[{id:'mock-tile',group:'mock-group',split:'development',image:'gray.jpg',rights:'Generated gray test tile; no outfit or person. Mock use only.',metadata:{schemaVersion:1}}]},null,2),{mode:0o600,flag:'wx'});
console.log(`Mock fixture ready. Start: npm run lab -- '${root}' '${resolve(root,'photos')}'`);
