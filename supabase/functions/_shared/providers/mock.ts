import type {Provider,Generation} from './types.ts';
import { criterionIds } from '../../../../packages/contracts/src/index.ts';
export function mockReport(partial=false) {
 return {kind:'report',summary:'The visible outfit has a clear, considered balance.',intentEvidence:null,criteria:criterionIds.map(id=>({id,applicable:id!=='intent',score:id==='intent'||(partial&&id==='finishing')?null:4,observation:id==='intent'?'No explicit occasion or style goal provided.':`Mock ${id} observation; this is a deterministic development fixture.`,explanation:'A real visual assessment requires the approved live provider.'})),strengths:['The visible pieces work together.'],diagnoses:[{id:'d1',principle:'finishing',observation:'The sleeves cover the layer beneath.'}],suggestions:[{diagnosisId:'d1',principle:'finishing',family:'fit_proportion',technique:'sleeve_adjustment',kind:'restyle',impact:'medium',requiresPurchase:false,targetAttribute:null,observation:'The sleeve length can be adjusted.',action:'Try turning the cuffs once.',reason:'This can give the layering a more deliberate finish.'}],limitations:partial?['Finishing details are outside the frame.']:['Mock assessment; no visual inference was performed.']};
}
export class MockProvider implements Provider {
 model='mock/outfit-v1'; calls=0;
 constructor(public scenario='success'){}
 async generate(input:Parameters<Provider['generate']>[0]):Promise<Generation>{
  this.calls++;
  if(this.scenario==='timeout') await new Promise((_,reject)=>{if(input.signal.aborted)reject(input.signal.reason);else input.signal.addEventListener('abort',()=>reject(input.signal.reason),{once:true});});
  if(this.scenario==='rate_limit') throw new Error('mock rejection');
  const usage={inputTokens:100,outputTokens:150,costMicrodollars:0};
  if(this.scenario==='tools'&&this.calls===1)return {toolCalls:[{id:'lookup-1',type:'function',function:{name:'lookup_clothing_guidance',arguments:'{"topic":"proportion"}'}}],usage};
  if(this.scenario==='retake')return {output:{kind:'retake',issues:['too_dark'],instructions:['Face a soft light source and keep the outfit in frame.']},usage};
  return {output:this.scenario==='malformed'?{summary:'broken'}:mockReport(this.scenario==='partial'),usage};
 }
}
