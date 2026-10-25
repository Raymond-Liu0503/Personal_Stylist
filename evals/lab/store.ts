import {createHash,randomUUID} from 'node:crypto';
import {readFile,writeFile,rename,mkdir,realpath,open} from 'node:fs/promises';
import {resolve,relative,dirname,sep} from 'node:path';
export const hash=(value:unknown)=>createHash('sha256').update(typeof value==='string'||value instanceof Uint8Array?value:JSON.stringify(value)).digest('hex');
export async function readJSON<T>(path:string):Promise<T>{return JSON.parse(await readFile(path,'utf8'));}
export async function atomic(path:string,value:unknown){const tmp=`${path}.${randomUUID()}.tmp`;await writeFile(tmp,JSON.stringify(value,null,2),{mode:0o600});await rename(tmp,path);}
export async function externalDirectory(path:string){
 await mkdir(path,{recursive:true,mode:0o700});const real=await realpath(path);let current=real;
 while(true){try{await realpath(resolve(current,'.git'));throw new Error('Lab data must be outside every Git checkout');}catch(e){if((e as NodeJS.ErrnoException).code!=='ENOENT')throw e;}const next=dirname(current);if(next===current)break;current=next;}
 return real;
}
export async function imagePath(root:string,path:string){const real=await realpath(resolve(root,path));const rel=relative(await realpath(root),real);if(rel==='..'||rel.startsWith(`..${sep}`)||rel.startsWith(sep))throw new Error('Image escapes external root');return real;}
export type Entry={id:string;split:'development'|'heldout';reserved:number;actual:number|null;status:'reserved'|'settled'};
export class Ledger{
 entries:Entry[]=[];blocked=false;
 constructor(readonly path:string){}
 async load(){try{const value=await readJSON<{entries:Entry[];blocked:boolean}>(this.path);this.entries=value.entries;this.blocked=value.blocked;}catch(e){if((e as NodeJS.ErrnoException).code!=='ENOENT')throw e;}}
 spent(split:Entry['split']){return this.entries.filter(e=>e.split===split).reduce((sum,e)=>sum+(e.actual??e.reserved),0);}
 async reserve(id:string,split:Entry['split'],amount:number){
  if(this.blocked||!Number.isSafeInteger(amount)||amount<0||this.entries.some(e=>e.id===id))throw new Error('Ledger blocked or invalid reservation');
  if(this.spent(split)+amount>(split==='development'?10:15)*1e6)throw new Error('Pilot budget exhausted: reduce the matrix; reserved uncertainty cannot be reused');
  this.entries.push({id,split,reserved:amount,actual:null,status:'reserved'});await this.save();
 }
 async settle(id:string,actual:number|null){const e=this.entries.find(e=>e.id===id);if(!e||e.status!=='reserved')throw new Error('Invalid settlement');if(actual!==null&&(!Number.isSafeInteger(actual)||actual<0))throw new Error('Invalid cost');if(actual!==null&&actual>e.reserved)this.blocked=true;e.actual=actual;e.status='settled';await this.save();}
 private save(){return atomic(this.path,{entries:this.entries,blocked:this.blocked});}
}
export async function lock(root:string){const path=resolve(root,'lab.lock');const fd=await open(path,'wx',0o600);await fd.writeFile(JSON.stringify({pid:process.pid,started:new Date().toISOString()}));return fd;}
