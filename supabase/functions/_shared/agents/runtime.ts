import { ReportSchema, promptFor, type OutfitAnalysisMetadata } from '../../../../packages/contracts/src/index.ts';
import type { Provider, Message, Usage, Generation } from '../providers/types.ts';
import { outfit, assessmentVersions } from './registry.ts';
import { parseModelOutput, outputJsonSchema, type CandidateField } from './model-schema.ts';
import { calculateOutfitScore } from './scoring.ts';
import { ApiError } from '../security/errors.ts';
import { selectSuggestions } from './suggestions.ts';
import type { ReasoningEffort } from '../providers/types.ts';
export type ValidationDiagnostic={round:number;stage:'provider'|'schema'|'scoring'|'report'|'candidates'|'selection';rejectedCount?:number;fields?:CandidateField[];candidateCount?:number;selectedCount?:number};
const forbidsPurchases=(constraints:readonly string[])=>(constraints).some(constraint=>
  /\b(no|avoid|without)\b.{0,30}\b(buy|buying|purchase|purchases|shopping|new (?:clothes|clothing|items|pieces))\b/i.test(constraint)
  ||/\b(do not|don['’]?t|cannot|can['’]?t)\b.{0,30}\b(buy|purchase|shop|spend)\b/i.test(constraint)
  ||/\b(use|wear|work with)\b.{0,30}\b(what|things|pieces|clothes|clothing|items)\b.{0,20}\b(own|have)\b/i.test(constraint)
);
export async function runOutfit(provider:Provider,input:{runId:string;metadata:OutfitAnalysisMetadata;image:Uint8Array;signal:AbortSignal;recentTechniques?:readonly string[];generationConfig?:{maxOutputTokens:number;temperature:number;reasoningEffort:ReasoningEffort}},onUsage:(usage:Usage)=>void=()=>{},onDiagnostic:(diagnostic:ValidationDiagnostic)=>void=()=>{}) {
  const messages:Message[]=[{role:'system',content:outfit.skillBundle.instructions},{role:'user',content:JSON.stringify({prompt:promptFor(input.metadata),context:input.metadata.context??{},recentTechniques:[...new Set(input.recentTechniques??[])]})}];
  for(let round=0;round<outfit.maxModelRounds;round++) {
    input.signal.throwIfAborted();
    let response:Generation;
    const generation=input.generationConfig??{maxOutputTokens:outfit.modelConfig.maxOutputTokens,temperature:outfit.modelConfig.temperature,reasoningEffort:outfit.modelConfig.reasoning};
    try{response=await provider.generate({messages,image:input.image,tools:[],schema:outputJsonSchema,signal:input.signal,...generation});}catch(e){if(e instanceof ApiError&&e.code==='INVALID_MODEL_OUTPUT')onDiagnostic({round:round+1,stage:'provider'});if(input.signal.aborted||e instanceof ApiError)throw e;throw new ApiError('PROVIDER_UNAVAILABLE',503,'The analysis service is unavailable.');}
    onUsage(response.usage);
    if(response.toolCalls?.length)throw new ApiError('INVALID_MODEL_OUTPUT',502);
    let stage:ValidationDiagnostic['stage']='schema';
    try {
      let rejected=0;
      const output=parseModelOutput(response.output,(rejectedCount,fields)=>{rejected=rejectedCount;onDiagnostic({round:round+1,stage:'candidates',rejectedCount,fields});});
      if(output.kind==='retake') return output;
      const {kind:_kind,intentEvidence,suggestions,diagnoses,...content}=output;
      stage='scoring';
      const {coverage:_coverage,...scoring}=calculateOutfitScore(content.criteria,input.metadata,intentEvidence);
      const purchaseConstraint=forbidsPurchases(input.metadata.context?.constraints??[]);
      const selected=selectSuggestions(suggestions,input.recentTechniques,{allowPurchases:!purchaseConstraint});
      onDiagnostic({round:round+1,stage:'selection',candidateCount:suggestions.length,selectedCount:selected.suggestions.length});
      if(selected.suggestions.length===0&&(rejected>0||diagnoses.length>0)){
        if(round+1<outfit.maxModelRounds){
          messages.push({role:'user',content:'The assessment had diagnosed improvements but no usable action after candidate validation. Return a complete final report with practical candidates linked to diagnoses. Use exact schema enums, matching technique/kind, and a targetAttribute for swaps. Restyles, removals, care, accessories, additions, and general garment swaps are allowed unless the user constraints forbid them. Keep every observation grounded in visible clothing. Do not pad advice.'});
          continue;
        }
        content.limitations=[...content.limitations.slice(0,5),'Suggested actions could not be validated for this assessment.'];
      }
      stage='report';
      return {kind:'report' as const,report:ReportSchema.parse({...content,suggestions:selected.suggestions,...scoring,schemaVersion:1,runId:input.runId,versions:assessmentVersions(provider.model)}),techniqueCodes:selected.techniqueCodes};
    } catch {
      onDiagnostic({round:round+1,stage});
      if(round===1) throw new ApiError('INVALID_MODEL_OUTPUT',502,'The assessment could not be validated. Please try a new analysis.');
      // Do not echo unvalidated provider text back into trusted messages or logging.
      messages.push({role:'user',content:'Return a final valid schema object. Check criterion uniqueness, visibility, and exact intent evidence. No tools remain.'});
    }
  }
  throw new ApiError('INVALID_MODEL_OUTPUT',502);
}
