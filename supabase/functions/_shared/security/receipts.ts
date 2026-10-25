import { z } from 'zod';
import { ReportSchema, type OutfitReport } from '../../../../packages/contracts/src/index.ts';
import { ApiError } from './errors.ts';
const encoder=new TextEncoder();
function canonical(x:unknown):string {if(x===null||typeof x!=='object')return JSON.stringify(x);if(Array.isArray(x))return `[${x.map(canonical).join(',')}]`;return `{${Object.keys(x).sort().map(k=>`${JSON.stringify(k)}:${canonical((x as Record<string,unknown>)[k])}`).join(',')}}`;}
const hex=(b:ArrayBuffer)=>Array.from(new Uint8Array(b),x=>x.toString(16).padStart(2,'0')).join('');
const Claims=z.object({userId:z.string().uuid(),runId:z.string().uuid(),hash:z.string().regex(/^[a-f0-9]{64}$/),expires:z.number().int()}).strict();
async function key(secret:string){if(secret.length<32)throw new Error('Receipt key must be at least 32 characters');return crypto.subtle.importKey('raw',encoder.encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign','verify']);}
async function hash(report:OutfitReport){return hex(await crypto.subtle.digest('SHA-256',encoder.encode(canonical(ReportSchema.parse(report)))));}
export async function signReceipt(secret:string,userId:string,report:OutfitReport,now=Date.now()) {
 const payload=btoa(JSON.stringify({userId,runId:report.runId,hash:await hash(report),expires:Math.floor(now/1000)+86400}));
 return `${payload}.${hex(await crypto.subtle.sign('HMAC',await key(secret),encoder.encode(payload)))}`;
}
export async function verifyReceipt(secret:string,userId:string,report:OutfitReport,receipt:string,now=Date.now()) {
 try{const pieces=receipt.split('.');if(pieces.length!==2)throw 0;const [payload,sig]=pieces;if(!/^[a-f0-9]{64}$/.test(sig))throw 0;
 const valid=await crypto.subtle.verify('HMAC',await key(secret),Uint8Array.from(sig.match(/../g)!,x=>parseInt(x,16)),encoder.encode(payload));if(!valid)throw 0;
 const claims=Claims.parse(JSON.parse(atob(payload)));if(claims.userId!==userId||claims.runId!==report.runId||claims.expires<=Math.floor(now/1000)||claims.hash!==await hash(report))throw 0;
 }catch{throw new ApiError('INVALID_RECEIPT',400,'This report cannot be saved. Its receipt is invalid or expired.');}
}
