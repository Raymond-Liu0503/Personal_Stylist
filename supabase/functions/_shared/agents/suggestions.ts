import type { z } from 'zod';
import type { InternalSuggestionSchema } from './model-schema.ts';

export type InternalSuggestion=z.infer<typeof InternalSuggestionSchema>;
const normalized=(value:string)=>value.trim().toLocaleLowerCase().replace(/\s+/g,' ');
const impactRank={high:0,medium:1,low:2} as const;

export function recentTechniqueMemory(rows:readonly {technique_codes:unknown}[]){
  return rows.slice(0,3).flatMap(row=>Array.isArray(row.technique_codes)?row.technique_codes.filter((code):code is string=>typeof code==='string'):[]);
}

export function resolveSuggestionTechnique(codes:unknown,index:number){
  if(!Array.isArray(codes)||!Number.isInteger(index)||index<0)return null;
  return typeof codes[index]==='string'?codes[index] as string:null;
}

export function selectSuggestions(candidates:readonly InternalSuggestion[],recentTechniques:readonly string[]=[],options:{allowPurchases?:boolean}={}){
  const actions=new Set<string>(),techniques=new Set<string>();
  const permitted=options.allowPurchases===false?candidates.filter(candidate=>!candidate.requiresPurchase):candidates;
  const unique=permitted.filter(candidate=>{
    const action=normalized(candidate.action);
    if(actions.has(action)||techniques.has(candidate.technique))return false;
    actions.add(action);techniques.add(candidate.technique);return true;
  });
  const recent=new Set(recentTechniques);
  const remaining=unique.map((candidate,index)=>({candidate,index,recent:recent.has(candidate.technique)})).sort((a,b)=>impactRank[a.candidate.impact]-impactRank[b.candidate.impact]||Number(a.recent)-Number(b.recent)||a.index-b.index);
  const selected:InternalSuggestion[]=[];
  while(remaining.length&&selected.length<3){
    const head=remaining[0];
    const tier=remaining.filter(item=>item.candidate.impact===head.candidate.impact&&item.recent===head.recent);
    const usedDiagnoses=new Set(selected.map(candidate=>candidate.diagnosisId)),usedFamilies=new Set(selected.map(candidate=>candidate.family));
    const next=tier.find(item=>!usedDiagnoses.has(item.candidate.diagnosisId)&&!usedFamilies.has(item.candidate.family))
      ??tier.find(item=>!usedDiagnoses.has(item.candidate.diagnosisId))
      ??tier.find(item=>!usedFamilies.has(item.candidate.family))??head;
    selected.push(next.candidate);remaining.splice(remaining.indexOf(next),1);
  }
  return {
    suggestions:selected.map(({diagnosisId:_diagnosisId,principle:_principle,family:_family,technique:_technique,impact:_impact,requiresPurchase:_requiresPurchase,targetAttribute:_target,...suggestion})=>suggestion),
    techniqueCodes:selected.map(candidate=>candidate.technique),
  };
}
