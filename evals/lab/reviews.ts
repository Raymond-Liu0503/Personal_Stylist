import {z} from 'zod';
import {shuffled} from '../../supabase/functions/_shared/agents/deep.ts';
import {hash} from './store.ts';
import type {Attempt} from './runner.ts';
import type {LabelSchema,PreferenceSchema} from './config.ts';
export type Pair={id:string;caseId:string;A:{attempt:string;variant:'final'|'original'|'repaired'};B:Pair['A']};
export function pairs(attempts:Attempt[],left:string,right:string,kind:'reports'|'repair'){
 const complete=attempts.filter(a=>a.state==='complete');const out:Pair[]=[];
 for(const a of complete.filter(a=>a.experiment.id===left)){
  const b=kind==='repair'?a:complete.find(b=>b.experiment.id===right&&b.caseId===a.caseId&&b.imageHash===a.imageHash&&b.live===a.live);
  if(!b||(kind==='repair'&&a.rounds.length<2)||kind==='reports'&&a.id===b.id)continue;
  const ids=[a.id,b.id].sort();const id=hash({ids,kind}).slice(0,40);
  const [A,B]=shuffled([{attempt:a.id,variant:kind==='repair'?'original' as const:'final' as const},{attempt:b.id,variant:kind==='repair'?'repaired' as const:'final' as const}],id);
  out.push({id,caseId:a.caseId,A,B});
 }
 return out;
}
export function blindReport(attempt:Attempt,variant:Pair['A']['variant']){
 if(variant!=='final'){const r=attempt.rounds[variant==='original'?0:1];return {summary:r.assessment.summary,criteria:r.assessment.criteria,strengths:r.assessment.strengths,limitations:r.assessment.limitations,suggestions:r.candidates.map(c=>({observation:c.action.observation,action:c.action.action,reason:c.action.reason}))};}
 const result=attempt.result;if(result?.kind!=='report')return {status:result?.kind??'failed',message:result?.message,issues:result?.issues,instructions:result?.instructions};
 const {summary,criteria,strengths,limitations,suggestions,score}=result.report;return {summary,criteria,strengths,limitations,suggestions,score};
}
export function metrics(attempts:Attempt[],labels:z.infer<typeof LabelSchema>[],votes:(z.infer<typeof PreferenceSchema>&{mapping:Pair})[]){
 return [...new Set(attempts.map(a=>a.experiment.id))].map(experiment=>{
  const rows=attempts.filter(a=>a.experiment.id===experiment);const done=rows.filter(a=>a.state==='complete');
  const ls=labels.filter(l=>rows.some(a=>a.id===l.attempt));
  const approved=(l:typeof ls[number],role?:'evidence'|'styling')=>{
   const round=rows.find(a=>a.id===l.attempt)?.rounds[l.round];const reviews=role?[round?.reviews[role]]:Object.values(round?.reviews??{});
   return reviews.length===(role?1:2)&&reviews.every(r=>r?.assessmentValid&&r.verdicts.some(v=>v.id===l.candidate&&v.revision===l.revision&&v.verdict==='pass'));
  };
  const preference={wins:0,losses:0,ties:0,neither:0};
  for(const v of votes){const a=rows.some(a=>a.id===v.mapping.A.attempt),b=rows.some(a=>a.id===v.mapping.B.attempt);if(a===b)continue;if(v.choice==='tie')preference.ties++;else if(v.choice==='neither')preference.neither++;else if(v.choice==='A'?a:b)preference.wins++;else preference.losses++;}
  const labelledUseful=ls.filter(l=>l.useful).length;
  return {experiment,attempts:rows.length,failed:rows.filter(a=>a.state==='failed').length,interrupted:rows.filter(a=>a.state==='running').length,emptyReports:done.filter(a=>a.result?.kind==='report'&&a.result.report.suggestions.length===0).length,unvalidated:done.filter(a=>a.result?.kind==='unvalidated').length,repairs:rows.filter(a=>a.events.some(e=>e.stage==='revision')).length,meanLatencyMs:rows.length?Math.round(rows.reduce((n,a)=>n+a.latencyMs,0)/rows.length):null,knownCostMicrodollars:rows.reduce((n,a)=>n+(a.costMicrodollars??0),0),unknownCostAttempts:rows.filter(a=>a.costMicrodollars===null||a.state==='running').length,preference,humanLabels:ls.length,groundingErrors:ls.filter(l=>l.groundingError).length,constraintFailures:ls.filter(l=>l.constraintFailure).length,semanticRedundancies:ls.filter(l=>l.redundant).length,usefulActionCoverage:labelledUseful?ls.filter(l=>l.useful&&approved(l)).length/labelledUseful:null,criticErrors:Object.fromEntries((['evidence','styling'] as const).map(role=>[role,{falseApprovals:ls.filter(l=>!l.useful&&approved(l,role)).length,falseRejections:ls.filter(l=>{const review=rows.find(a=>a.id===l.attempt)?.rounds[l.round]?.reviews[role];return l.useful&&review?.verdicts.some(v=>v.id===l.candidate&&v.revision===l.revision&&v.verdict!=='pass');}).length,unreviewedLabels:ls.filter(l=>!rows.find(a=>a.id===l.attempt)?.rounds[l.round]?.reviews[role]).length}]))};
 });
}
