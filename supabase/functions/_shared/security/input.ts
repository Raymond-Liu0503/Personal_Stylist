import { MetadataSchema } from '../../../../packages/contracts/src/index.ts';
import { ApiError } from './errors.ts';
export async function readLimited(stream:ReadableStream<Uint8Array>|null,limit:number,signal?:AbortSignal){
 if(!stream)throw new ApiError('INVALID_INPUT');
 const reader=stream.getReader();const chunks:Uint8Array[]=[];let size=0;
 const abort=()=>{void reader.cancel().catch(()=>{});};signal?.addEventListener('abort',abort,{once:true});
 try{while(true){signal?.throwIfAborted();const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>limit){await reader.cancel();throw new ApiError('INVALID_INPUT',413,'The upload is too large.');}chunks.push(value);}signal?.throwIfAborted();}finally{signal?.removeEventListener('abort',abort);reader.releaseLock();}
 const bytes=new Uint8Array(size);let offset=0;for(const c of chunks){bytes.set(c,offset);offset+=c.length;}return bytes;
}
// Validate JPEG marker/scan structure and discard APPn and COM, including EXIF/GPS/ICC.
// No raster transform is performed at the edge. Only baseline/progressive 8-bit JPEG accepted.
export function sanitizeJpeg(data:Uint8Array){
 const bad=()=>new ApiError('INVALID_INPUT',400,'Use a valid JPEG photo up to 1,600 pixels and 2 MiB.');
 if(data.length>2*1024*1024||data.length<20||data[0]!==255||data[1]!==216)throw bad();
 const parts:Uint8Array[]=[data.subarray(0,2)];let p=2;let width=0,height=0,scans=0,frame=false,quant=false,huffman=false,ended=false;
 const components=new Map<number,number>(),tables=new Set<number>(),codes=new Set<number>();let progressive=false;
 while(p<data.length){
  const start=p;if(data[p++]!==255)throw bad();while(data[p]===255)p++;const marker=data[p++];
  if(marker===217){if(p!==data.length||!frame||!scans||!quant||!huffman)throw bad();parts.push(new Uint8Array([255,217]));ended=true;break;}
  if(marker===0||marker===216||(marker>=208&&marker<=215)||marker===1||p+2>data.length)throw bad();
  const length=(data[p]<<8)|data[p+1];if(length<2||p+length>data.length)throw bad();const end=p+length,payload=p+2;
  if(marker>=192&&marker<=207&&![196,200,204].includes(marker)){
   if(![192,194].includes(marker)||frame||length<11||data[p+2]!==8)throw bad();
   height=(data[p+3]<<8)|data[p+4];width=(data[p+5]<<8)|data[p+6];const channels=data[p+7];
   if(![1,3].includes(channels)||length!==8+3*channels||!width||!height||Math.max(width,height)>1600)throw bad();frame=true;progressive=marker===194;
   for(let i=0;i<channels;i++){const at=p+8+3*i,id=data[at],sampling=data[at+1],table=data[at+2];if(components.has(id)||!(sampling>>4)||!(sampling&15)||(sampling>>4)>4||(sampling&15)>4||table>3)throw bad();components.set(id,table);}
  }
  if(marker===219){let q=p+2;if(q===end)throw bad();while(q<end){const spec=data[q++],precision=spec>>4,id=spec&15;if(precision>1||id>3)throw bad();const size=64*(precision+1);if(q+size>end)throw bad();for(let i=0;i<64;i++){if(precision?((data[q+2*i]<<8)|data[q+2*i+1])===0:data[q+i]===0)throw bad();}q+=size;tables.add(id);}quant=true;}
  if(marker===196){let q=p+2;if(q===end)throw bad();while(q<end){const spec=data[q++];if((spec>>4)>1||(spec&15)>3||q+16>end)throw bad();let count=0,available=1;for(let i=0;i<16;i++){available=available*2-data[q+i];if(available<0)throw bad();count+=data[q+i];}q+=16;if(!count||count>256||q+count>end)throw bad();q+=count;codes.add(spec);}huffman=true;}
  if(marker===221&&length!==4)throw bad();
  if(![192,194,196,219,218,221,254].includes(marker)&&!(marker>=224&&marker<=239))throw bad();
  if(!((marker>=224&&marker<=239)||marker===254))parts.push(data.subarray(start,end));p=end;
  if(marker===218){
   if(!frame||length<6)throw bad();const countComponents=data[payload];if(!countComponents||countComponents>components.size||length!==6+2*countComponents)throw bad();const ids=new Set<number>();
   const ss=data[end-3],se=data[end-2],approx=data[end-1];
   if(!progressive&&(ss!==0||se!==63||approx!==0))throw bad();
   if(progressive&&(ss>se||se>63||(ss===0&&se!==0)||(ss>0&&countComponents!==1)||(approx>>4)>13||(approx&15)>13||((approx>>4)!==0&&(approx>>4)!==(approx&15)+1)))throw bad();
   for(let i=0;i<countComponents;i++){const id=data[payload+1+2*i],selectors=data[payload+2+2*i];if(ids.has(id)||!components.has(id)||!tables.has(components.get(id)!)||(selectors>>4)>3||(selectors&15)>3)throw bad();ids.add(id);if((!progressive||ss===0&&(approx>>4)===0)&&!codes.has(selectors>>4))throw bad();if((!progressive||ss>0)&&!codes.has(16+(selectors&15)))throw bad();}
   scans++;const scanStart=p;let count=0;
   while(p<data.length){if(data[p]!==255){p++;count++;continue;}if(data[p+1]===0||(data[p+1]>=208&&data[p+1]<=215)){p+=2;count++;continue;}break;}
   if(count===0)throw bad();parts.push(data.subarray(scanStart,p));
  }
 }
 if(!ended)throw bad();const output=new Uint8Array(parts.reduce((n,b)=>n+b.length,0));let offset=0;for(const b of parts){output.set(b,offset);offset+=b.length;}return {bytes:output,width,height};
}
export async function parseAnalysis(request:Request,signal:AbortSignal){
 const type=request.headers.get('content-type')??'';if(!type.startsWith('multipart/form-data;'))throw new ApiError('INVALID_INPUT');
 const bytes=await readLimited(request.body,3*1024*1024,signal);
 let form:FormData;try{form=await new Response(bytes as BodyInit,{headers:{'content-type':type}}).formData();}catch{throw new ApiError('INVALID_INPUT');}
 if([...form.keys()].length!==2 || form.getAll('image').length!==1||form.getAll('metadata').length!==1)throw new ApiError('INVALID_INPUT');
 const image=form.get('image'),raw=form.get('metadata');if(!(image instanceof File)||image.type!=='image/jpeg'||typeof raw!=='string'||raw.length>6000)throw new ApiError('INVALID_INPUT');
 let metadata;try{metadata=MetadataSchema.parse(JSON.parse(raw));}catch{throw new ApiError('INVALID_INPUT',400,'Check your prompt and photo, then try again.');}
 return {metadata,image:sanitizeJpeg(new Uint8Array(await image.arrayBuffer())).bytes};
}
