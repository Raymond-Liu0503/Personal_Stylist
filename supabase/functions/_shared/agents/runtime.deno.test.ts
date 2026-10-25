import { MetadataSchema } from '../../../../packages/contracts/src/index.ts';
import { runOutfit } from './runtime.ts';
import { MockProvider } from '../providers/mock.ts';
Deno.test('Deno imports shared contracts and completes mock outfit assessment',async()=>{
 const metadata=MetadataSchema.parse({schemaVersion:1});
 const result=await runOutfit(new MockProvider(),{runId:crypto.randomUUID(),metadata,image:new Uint8Array(),signal:new AbortController().signal});
 if(result.kind!=='report'||result.report.overallScore!==8)throw new Error('Unexpected mock result');
});
