import {execFileSync} from 'node:child_process';
import {mkdtempSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

// Local only: backend 180s < gateway 195s < iOS request 200s < resource 210s.
export const gatewayTimeoutMs=195000;
export function configureGatewayTimeout(yaml){
 const lines=yaml.split('\n');
 const starts=lines.flatMap((line,i)=>line==='  - name: functions-v1'?[i]:[]);
 if(starts.length!==1)throw new Error('Expected exactly one functions-v1 service');
 const start=starts[0];
 let end=lines.findIndex((line,i)=>i>start&&line.startsWith('  - name: '));
 if(end===-1)end=lines.length;
 const timeoutLines=lines.flatMap((line,i)=>i>start&&i<end&&/^    read_timeout: \d+\s*$/.test(line)?[i]:[]);
 if(timeoutLines.length!==1)throw new Error('Expected one functions-v1 read_timeout');
 lines[timeoutLines[0]]=`    read_timeout: ${gatewayTimeoutMs}`;
 for(let i=start;i<end;i++)if(lines[i].includes('# Set request idle timeout to 150s'))lines[i]='    # Local Deep analysis: allow the 180s handler deadline to return a response.';
 return lines.join('\n');
}

function main(){
 const root=fileURLToPath(new URL('../',import.meta.url));
 const config=readFileSync(join(root,'supabase/config.toml'),'utf8');
 const project=config.match(/^project_id\s*=\s*"([a-zA-Z0-9_-]+)"\s*$/m)?.[1];
 if(!project)throw new Error('Cannot determine local Supabase project');
 const container=`supabase_kong_${project}`;
 let lastCommand='';
 const docker=(...args)=>{lastCommand=args.join(' ');return execFileSync('docker',args,{encoding:'utf8',stdio:['ignore','pipe','pipe'],timeout:20000});};
 const dir=mkdtempSync(join(tmpdir(),'stylist-gateway-'));
 const original=join(dir,'original.yml'),updated=join(dir,'updated.yml');
 const remote='/tmp/stylist-gateway-validated.yml';
 let replaced=false;
 try{
  docker('cp',`${container}:/home/kong/kong.yml`,original);
  const yaml=readFileSync(original,'utf8');
  writeFileSync(updated,configureGatewayTimeout(yaml),{mode:0o600});
  docker('cp',updated,`${container}:${remote}`);
  docker('exec','--user','0',container,'chown','kong:nogroup',remote);
  docker('exec',container,'kong','config','parse',remote);
  docker('cp',updated,`${container}:/home/kong/kong.yml`);replaced=true;
  docker('exec','--user','0',container,'chown','kong:nogroup','/home/kong/kong.yml');
  docker('exec',container,'kong','reload');
  // Verify the active service, not just the configuration file.
  let verified=false;
  for(let attempt=0;attempt<10;attempt++){
   try{
    const active=JSON.parse(docker('exec',container,'wget','-qO-','http://127.0.0.1:8001/services/functions-v1'));
    if(active.read_timeout===gatewayTimeoutMs){verified=true;break;}
   }catch{/* A graceful reload may briefly make the admin listener unavailable. */}
   Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,500);
  }
  if(!verified)throw new Error('Active gateway timeout verification failed');
  console.log(`Local functions gateway verified: ${gatewayTimeoutMs/1000}s read timeout. No model calls or database changes.`);
 }catch{
  const failedCommand=lastCommand;
  if(replaced){
   try{docker('cp',original,`${container}:/home/kong/kong.yml`);docker('exec','--user','0',container,'chown','kong:nogroup','/home/kong/kong.yml');docker('exec',container,'kong','reload');}
   catch{throw new Error('Gateway update and rollback failed; inspect the local Kong container before retrying.');}
  }
  // Docker output/configuration may contain local credentials. Do not print it.
  throw new Error(`Local gateway update failed at: docker ${failedCommand}. No configuration contents were logged.`);
 }finally{
  try{docker('exec',container,'rm','-f',remote);}catch{}
  rmSync(dir,{recursive:true,force:true});
 }
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{main();}catch(error){console.error(error.message);process.exitCode=1;}
}
