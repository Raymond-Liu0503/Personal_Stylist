import { CriteriaSchema, type CriterionAssessment, type OutfitAnalysisMetadata } from '../../../../packages/contracts/src/index.ts';
import { ApiError } from '../security/errors.ts';
// Finishing includes visible garment condition and execution.
export const weights = {silhouette:25,colour:15,coherence:15,finishing:20,intent:25} as const;
export function calculateOutfitScore(criteria:CriterionAssessment[], metadata:OutfitAnalysisMetadata, intentEvidence:string|null) {
  CriteriaSchema.parse(criteria);
  const supplied = [metadata.prompt?.trim(),metadata.context?.occasion,metadata.context?.desiredStyle,...(metadata.context?.constraints??[])].filter((x):x is string=>!!x);
  const intent = criteria.find(c=>c.id==='intent')!;
  const supported = !!intentEvidence?.trim() && supplied.some(s=>s.includes(intentEvidence!));
  if (intent.applicable !== supported || (!intent.applicable && intentEvidence!==null)) throw new ApiError('INVALID_MODEL_OUTPUT',502,'The assessment could not be validated.');
  // The first four weights remain applicable even if obscured. Missing visibility reduces coverage.
  if(criteria.some(c=>c.id!=='intent' && !c.applicable)) throw new ApiError('INVALID_MODEL_OUTPUT',502);
  const applicableWeight = 75 + (supported?25:0);
  const assessed = criteria.filter(c=>c.applicable && c.score!==null);
  const assessedWeight = assessed.reduce((n,c)=>n+weights[c.id],0);
  const coverage=assessedWeight/applicableWeight;
  const overallScore=coverage>=0.75?Math.round(4*assessed.reduce((n,c)=>n+weights[c.id]*c.score!,0)/assessedWeight)/2:null;
  return {overallScore,verdict:overallScore===null?null:overallScore>=7?'works_well' as const:'could_improve' as const,status:assessedWeight<applicableWeight?'partial' as const:'complete' as const,coverage};
}
