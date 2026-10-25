import type {Provider} from './types.ts';

// One accumulator per user analysis. Uncertainty is sticky: one successful critic
// must never erase a sibling's ambiguous dispatch or missing provider usage.
export function measuredProvider(provider:Provider){
 let inputTokens=0,outputTokens=0,totalCost=0,unknown=false;
 const pending=new Set<Promise<unknown>>();
 const measured:Provider={model:provider.model,generate(args){
  let settle!:()=>void;
  const tracked=new Promise<void>(resolve=>{settle=resolve;});
  pending.add(tracked);
  const call=(async()=>{
   try{
    const result=await provider.generate(args);
    const u=result.usage;
    inputTokens+=u.inputTokens;outputTokens+=u.outputTokens;
    if(u.costMicrodollars===null||!Number.isSafeInteger(u.costMicrodollars)||u.costMicrodollars<0)unknown=true;
    else totalCost+=u.costMicrodollars;
    return result;
   }catch(error){unknown=true;throw error;}
  })();
  void call.then(()=>{settle();pending.delete(tracked);},()=>{settle();pending.delete(tracked);});
  return call;
 }};
 return {provider:measured,async drain(){await Promise.allSettled([...pending]);},snapshot(){return {inputTokens,outputTokens,cost:unknown||pending.size?null:totalCost};}};
}
