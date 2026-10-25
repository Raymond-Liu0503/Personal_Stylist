import { z } from 'zod';
export const POLICY_VERSION = '2026-09-01';
export const DEFAULT_PROMPT = 'Assess whether this outfit works overall and suggest improvements.';
const text = (max: number) => z.string().trim().min(1).max(max).refine(s => !/<\/?[a-z][^>]*>|https?:\/\//i.test(s), 'Plain text only');
export const criterionIds = ['silhouette','colour','coherence','finishing','intent'] as const;
export const MetadataSchema = z.object({schemaVersion:z.literal(1),prompt:z.string().max(1000).optional(),context:z.object({occasion:text(160).optional(),desiredStyle:text(160).optional(),constraints:z.array(text(160)).max(10).optional()}).strict().optional()}).strict();
export type OutfitAnalysisMetadata = z.infer<typeof MetadataSchema>;
export const CriterionSchema = z.object({id:z.enum(criterionIds),applicable:z.boolean(),score:z.number().int().min(0).max(5).nullable(),observation:text(500),explanation:text(700)}).strict().refine(c=>c.applicable || c.score===null, 'Unavailable criteria must have null scores');
export const CriteriaSchema = z.array(CriterionSchema).length(5).refine(c=>new Set(c.map(x=>x.id)).size===5,'Criteria must be unique');
export const suggestionKinds = ['restyle','remove','care','swap','add'] as const;
export const SuggestionSchema = z.object({observation:text(500),action:text(500),reason:text(500),kind:z.enum(suggestionKinds).optional()}).strict();
export const ReportSchema = z.object({schemaVersion:z.literal(1),runId:z.string().uuid(),status:z.enum(['complete','partial']),summary:text(700),overallScore:z.number().min(0).max(10).multipleOf(0.5).nullable(),verdict:z.enum(['works_well','could_improve']).nullable(),criteria:CriteriaSchema,strengths:z.array(text(500)).max(5),suggestions:z.array(SuggestionSchema).max(5),limitations:z.array(text(500)).max(6),versions:z.object({agent:text(100),skill:text(100),rubric:text(100),model:text(150)}).strict()}).strict();
export type OutfitReport = z.infer<typeof ReportSchema>;
export type CriterionAssessment = z.infer<typeof CriterionSchema>;
export const RetakeSchema = z.object({kind:z.literal('retake'),issues:z.array(z.enum(['no_outfit','multiple_people','too_dark','blurred','too_cropped','unsupported_content'])).min(1).max(6),instructions:z.array(text(350)).min(1).max(6)}).strict();
export const AnalysisResponseSchema = z.union([z.object({kind:z.literal('report'),report:ReportSchema,receipt:z.string().max(1500)}).strict(),RetakeSchema]);
export type AnalysisResponse = z.infer<typeof AnalysisResponseSchema>;
export const PreferencesSchema = z.object({desiredStyle:text(160).optional(),constraints:z.array(text(160)).max(10).optional()}).strict();
export const ConsentSchema = z.object({policyVersion:z.literal(POLICY_VERSION),accepted:z.boolean(),adultConfirmed:z.boolean()}).strict().refine(c=>!c.accepted || c.adultConfirmed,'Adult confirmation required');
export const SaveReportSchema = z.object({report:ReportSchema,receipt:z.string().max(1500)}).strict();
export const ReportFeedbackSchema = z.object({savedReportId:z.string().uuid().optional(),helpful:z.boolean(),issues:z.array(z.enum(['invented_details','unhelpful','offensive','incorrect_score','other'])).max(5)}).strict();
export const SuggestionFeedbackSchema = z.object({runId:z.string().uuid(),suggestionIndex:z.number().int().min(0).max(2),helpful:z.boolean()}).strict();
export const FeedbackSchema = z.union([ReportFeedbackSchema,SuggestionFeedbackSchema]);
export const DeleteAccountSchema = z.object({authorizationCode:z.string().min(1).max(4000)}).strict();
export const ErrorCodeSchema = z.enum(['INVALID_INPUT','UNAUTHENTICATED','CONSENT_REQUIRED','BETA_REQUIRED','QUOTA_EXHAUSTED','BUDGET_EXHAUSTED','DUPLICATE_ACTIVE','DUPLICATE_FINISHED','ANALYSIS_ACTIVE','PROVIDER_UNAVAILABLE','INVALID_MODEL_OUTPUT','TIMEOUT','DISABLED','NOT_FOUND','INVALID_RECEIPT','REAUTHENTICATION_REQUIRED','DELETION_PENDING','INTERNAL']);
export type ErrorCode = z.infer<typeof ErrorCodeSchema>;
export const ApiErrorSchema = z.object({error:z.object({code:ErrorCodeSchema,message:z.string().max(500)}).strict()}).strict();
export const BootstrapSchema = z.object({analysisMode:z.enum(['mock','live']).optional(),dailyQuotaExempt:z.boolean().optional(),profile:PreferencesSchema,policyVersion:z.string(),consentAccepted:z.boolean(),features:z.object({outfit:z.boolean()}).strict(),remainingQuota:z.number().int().min(0).max(3),betaAccess:z.boolean()}).strict();
export type Bootstrap = z.infer<typeof BootstrapSchema>;
export const SavedReportSchema = z.object({id:z.string().uuid(),created_at:z.string(),report:ReportSchema}).strict();
export const HistorySchema = z.object({items:z.array(SavedReportSchema),nextCursor:z.string().nullable()}).strict();
export const promptFor = (m:OutfitAnalysisMetadata) => m.prompt?.trim() || DEFAULT_PROMPT;

export const intentPresets = [
 {id:'general',label:'General',context:{}},
 {id:'everyday',label:'Everyday',context:{occasion:'Everyday activities'}},
 {id:'work',label:'Work',context:{occasion:'Work, without assuming a specific workplace dress code'}},
 {id:'date',label:'Date',context:{occasion:'A date, without assuming venue or formality'}},
 {id:'evening_out',label:'Evening out',context:{occasion:'An evening out'}},
 {id:'formal_event',label:'Formal event',context:{occasion:'A formal event, without assuming black tie'}},
 {id:'more_polished',label:'More polished',context:{desiredStyle:'A more polished presentation'}},
 {id:'more_expressive',label:'More expressive',context:{desiredStyle:'A more expressive presentation'}},
 {id:'custom',label:'Custom',context:{}},
] as const;
export type IntentPresetId = typeof intentPresets[number]['id'];
export const IntentSelectionSchema = z.object({id:z.enum(intentPresets.map(p=>p.id) as [IntentPresetId,...IntentPresetId[]]),custom:z.string().max(160)}).strict().superRefine((v,ctx)=>{if(v.id==='custom'&&!text(160).safeParse(v.custom).success)ctx.addIssue({code:'custom',path:['custom'],message:'Enter a plain-text intent (1–160 characters).'});});
export const initialIntent = {id:'general' as IntentPresetId,custom:''};
export function contextForIntent(selection:z.infer<typeof IntentSelectionSchema>):NonNullable<OutfitAnalysisMetadata['context']> {
 const value=IntentSelectionSchema.parse(selection);
 return value.id==='custom'?{desiredStyle:value.custom.trim()}:intentPresets.find(p=>p.id===value.id)!.context;
}
export function mergeAssessmentContext(preferences:z.infer<typeof PreferencesSchema>,context:OutfitAnalysisMetadata['context']) {return {...preferences,...context};}
