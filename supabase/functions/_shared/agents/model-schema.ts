import { z } from 'zod';
import { ReportSchema, RetakeSchema, SuggestionSchema, suggestionKinds } from '../../../../packages/contracts/src/index.ts';
export const suggestionFamilies = ['fit_proportion','layering','colour','texture','footwear','accessories','editing_removal','garment_care'] as const;
export const suggestionPrinciples = ['proportion','balance','emphasis','rhythm','colour','texture','finishing','intent'] as const;
export const suggestionTechniques = ['tuck','untuck','sleeve_adjustment','hem_adjustment','open_layer','close_layer','add_layer','remove_layer','swap_layer','volume_swap','length_swap','colour_repetition','colour_substitution','texture_change','pattern_change','footwear_swap','accessory_add','accessory_remove','accessory_reposition','garment_care'] as const;
export const suggestionImpacts = ['high','medium','low'] as const;
export const swapAttributes = ['length','volume','colour_value','texture','pattern','formality'] as const;
export const diagnosisIds = ['d1','d2','d3','d4','d5','d6'] as const;
export const techniqueKinds:Record<typeof suggestionTechniques[number],typeof suggestionKinds[number]>={tuck:'restyle',untuck:'restyle',sleeve_adjustment:'restyle',hem_adjustment:'restyle',open_layer:'restyle',close_layer:'restyle',add_layer:'add',remove_layer:'remove',swap_layer:'swap',volume_swap:'swap',length_swap:'swap',colour_repetition:'restyle',colour_substitution:'swap',texture_change:'swap',pattern_change:'swap',footwear_swap:'swap',accessory_add:'add',accessory_remove:'remove',accessory_reposition:'restyle',garment_care:'care'};
export const DiagnosisSchema=z.object({id:z.enum(diagnosisIds),principle:z.enum(suggestionPrinciples),observation:z.string().trim().min(1).max(500)}).strict();
export const InternalSuggestionSchema = SuggestionSchema.required({kind:true}).extend({
  diagnosisId:z.enum(diagnosisIds),principle:z.enum(suggestionPrinciples),family:z.enum(suggestionFamilies),technique:z.enum(suggestionTechniques),kind:z.enum(suggestionKinds),impact:z.enum(suggestionImpacts),requiresPurchase:z.boolean(),targetAttribute:z.enum(swapAttributes).nullable(),
}).strict().superRefine((value,ctx)=>{
  if(value.kind!==techniqueKinds[value.technique])ctx.addIssue({code:'custom',path:['kind'],message:'Kind must match the normalized technique.'});
  if(value.kind==='swap' && value.targetAttribute===null)ctx.addIssue({code:'custom',path:['targetAttribute'],message:'Swaps must identify the changed attribute.'});
  // A valid attribute on a non-swap is harmless metadata; do not discard the
  // action for it. Swaps still require a concrete attribute.
  if(value.technique==='tuck'||value.technique==='untuck'){
    if(value.principle!=='proportion')ctx.addIssue({code:'custom',path:['principle'],message:'Tucking must diagnose proportion.'});
    // Visual grounding is a semantic requirement in the specialist prompt;
    // English keyword matching rejects valid paraphrases without proving it.
  }
  if(value.family==='accessories'){
    if(!['balance','emphasis'].includes(value.principle))ctx.addIssue({code:'custom',path:['principle'],message:'Accessory advice requires a balance or emphasis need.'});
  }
});
const ModelReportBase = ReportSchema.pick({summary:true,criteria:true,strengths:true,suggestions:true,limitations:true}).extend({kind:z.literal('report'),diagnoses:z.array(DiagnosisSchema).max(6),suggestions:z.array(InternalSuggestionSchema).max(6),intentEvidence:z.string().trim().min(1).max(1000).nullable()}).strict();
export const ModelReportSchema = ModelReportBase.superRefine((value,ctx)=>{
  if(new Set(value.diagnoses.map(d=>d.id)).size!==value.diagnoses.length)ctx.addIssue({code:'custom',path:['diagnoses'],message:'Diagnosis IDs must be unique.'});
  for(const [index,candidate] of value.suggestions.entries()){
    const diagnosis=value.diagnoses.find(d=>d.id===candidate.diagnosisId);
    if(!diagnosis)ctx.addIssue({code:'custom',path:['suggestions',index,'diagnosisId'],message:'Candidate must reference a diagnosis.'});
    else if(diagnosis.principle!==candidate.principle)ctx.addIssue({code:'custom',path:['suggestions',index,'principle'],message:'Candidate principle must match its diagnosis.'});
  }
});
export const ModelOutputSchema = z.union([ModelReportSchema,RetakeSchema]);
// Explicit provider schema avoids effects/unions silently weakening strict structured output.
const boundedText={type:'string',minLength:1,maxLength:700};
export const outputJsonSchema = {type:'object',additionalProperties:false,properties:{kind:{type:'string',enum:['report','retake']},summary:{type:['string','null'],minLength:1,maxLength:700},criteria:{type:'array',maxItems:5,items:{type:'object',additionalProperties:false,properties:{id:{type:'string',enum:['silhouette','colour','coherence','finishing','intent']},applicable:{type:'boolean'},score:{type:['integer','null'],minimum:0,maximum:5},observation:{...boundedText,maxLength:500},explanation:boundedText},required:['id','applicable','score','observation','explanation']}},strengths:{type:'array',maxItems:5,items:{...boundedText,maxLength:500}},diagnoses:{type:'array',maxItems:6,items:{type:'object',additionalProperties:false,properties:{id:{type:'string',enum:diagnosisIds},principle:{type:'string',enum:suggestionPrinciples},observation:{...boundedText,maxLength:500}},required:['id','principle','observation']}},suggestions:{type:'array',maxItems:6,items:{type:'object',additionalProperties:false,properties:{diagnosisId:{type:'string',enum:diagnosisIds},principle:{type:'string',enum:suggestionPrinciples},family:{type:'string',enum:suggestionFamilies},technique:{type:'string',enum:suggestionTechniques},kind:{type:'string',enum:suggestionKinds},impact:{type:'string',enum:suggestionImpacts},requiresPurchase:{type:'boolean'},targetAttribute:{type:['string','null'],enum:[...swapAttributes,null]},observation:{...boundedText,maxLength:500},action:{...boundedText,maxLength:500},reason:{...boundedText,maxLength:500}},required:['diagnosisId','principle','family','technique','kind','impact','requiresPurchase','targetAttribute','observation','action','reason']}},limitations:{type:'array',maxItems:6,items:{...boundedText,maxLength:500}},intentEvidence:{type:['string','null'],minLength:1,maxLength:1000},issues:{type:'array',maxItems:6,items:{type:'string',enum:['no_outfit','multiple_people','too_dark','blurred','too_cropped','unsupported_content']}},instructions:{type:'array',maxItems:6,items:{...boundedText,maxLength:350}}},required:['kind','summary','criteria','strengths','diagnoses','suggestions','limitations','intentEvidence','issues','instructions']};
// Validate the report envelope independently before discarding unusable optional
// candidates. Required assessment fields and retake validation remain strict.
const CandidateReportSchema=ModelReportBase.omit({suggestions:true}).extend({suggestions:z.array(z.unknown()).max(6)}).strict();
const candidateFields=['diagnosisId','principle','family','technique','kind','impact','requiresPurchase','targetAttribute','observation','action','reason'] as const;
export type CandidateField=typeof candidateFields[number]|'shape';
function parseCandidates(raw:unknown,onRejected:(count:number,fields:CandidateField[])=>void){
  const report=CandidateReportSchema.parse(raw);
  const fields=new Set<CandidateField>();
  const suggestions=report.suggestions.flatMap(candidate=>{
    const parsed=InternalSuggestionSchema.safeParse(candidate);
    if(!parsed.success)for(const issue of parsed.error.issues){
      const field=candidateFields.find(field=>field===issue.path[0]);
      fields.add(field??'shape');
    }
    if(!parsed.success)return [];
    const diagnosis=report.diagnoses.find(item=>item.id===parsed.data.diagnosisId);
    if(!diagnosis){fields.add('diagnosisId');return [];}
    if(diagnosis.principle!==parsed.data.principle){fields.add('principle');return [];}
    return [parsed.data];
  });
  const rejected=report.suggestions.length-suggestions.length;
  if(rejected)onRejected(rejected,[...fields]);
  return ModelReportSchema.parse({...report,suggestions});
}
export function parseModelOutput(raw:unknown,onRejected?:(count:number,fields:CandidateField[])=>void) {
  const parse=(value:unknown)=>onRejected&&value&&typeof value==='object'&&'kind' in value&&value.kind==='report'
    ?parseCandidates(value,onRejected):ModelOutputSchema.parse(value);
  // Providers with strict mode require a fixed envelope. Public/internal discriminants stay narrow.
  if(raw && typeof raw==='object' && 'issues' in raw && 'summary' in raw) {
    const x=raw as Record<string,unknown>;
    const allowed=Object.keys((outputJsonSchema as {properties:object}).properties);
    if(Object.keys(x).some(k=>!allowed.includes(k))) return parse(raw);
    if(x.kind==='retake' && x.summary===null && x.intentEvidence===null && ['criteria','strengths','diagnoses','suggestions','limitations'].every(k=>Array.isArray(x[k]) && (x[k] as unknown[]).length===0)) return ModelOutputSchema.parse({kind:x.kind,issues:x.issues,instructions:x.instructions});
    if(x.kind==='report' && Array.isArray(x.issues) && x.issues.length===0 && Array.isArray(x.instructions) && x.instructions.length===0) {
      const {issues:_i,instructions:_n,...report}=x; return parse(report);
    }
  }
  return parse(raw);
}
