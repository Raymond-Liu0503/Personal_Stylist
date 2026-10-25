import {test} from 'node:test';
import assert from 'node:assert/strict';
import {measuredProvider} from '../supabase/functions/_shared/providers/accounting.ts';
import type {Provider} from '../supabase/functions/_shared/providers/types.ts';
const usage={inputTokens:5,outputTokens:7,costMicrodollars:9};
const req={messages:[],tools:[],schema:{},signal:AbortSignal.timeout(1000),maxOutputTokens:20,reasoningEffort:'low' as const};
test('usage aggregates every concurrent call and known amounts settle',async()=>{
 const p:Provider={model:'test',generate:async()=>({output:{},usage})};const a=measuredProvider(p);
 await Promise.all([a.provider.generate(req),a.provider.generate(req)]);await a.drain();assert.deepEqual(a.snapshot(),{inputTokens:10,outputTokens:14,cost:18});
});
test('unknown usage and one ambiguous parallel failure are sticky',async()=>{
 const p:Provider={model:'test',generate:async()=>{if(Math.random()<0)throw Error();return {output:{},usage}}};
 let i=0;const mixed:Provider={model:'test',generate:async()=>{if(++i===1)throw Error('ambiguous');return p.generate(req);}};
 const a=measuredProvider(mixed);await Promise.allSettled([a.provider.generate(req),a.provider.generate(req)]);await a.drain();assert.equal(a.snapshot().cost,null);assert.equal(a.snapshot().inputTokens,5);
 const missing:Provider={model:'missing',generate:async()=>({output:{},usage:{...usage,costMicrodollars:null}})};const b=measuredProvider(missing);await b.provider.generate(req);assert.equal(b.snapshot().cost,null);
});
test('settlement drains pending calls before reporting',async()=>{
 let release!:()=>void;const wait=new Promise<void>(r=>release=r);const p:Provider={model:'test',generate:async()=>{await wait;return {output:{},usage};}};const a=measuredProvider(p);const started=a.provider.generate(req);const draining=a.drain();release();await Promise.all([started,draining]);assert.equal(a.snapshot().cost,9);
});
