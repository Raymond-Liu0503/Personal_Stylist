export const productionModel={
  id:'google/gemini-3.1-flash-lite',
  maxOutputTokens:3600,
  temperature:1,
  reasoning:'low',
} as const;

export const comparisonModels=[productionModel.id,'google/gemini-3.1-pro-preview'] as const;
export type ComparisonModel=typeof comparisonModels[number];

export type Selection={stylistTier:'everyday'|'expert';analysisDepth:'quick'|'deep'};
export type AnalysisProfile=Readonly<Selection & {
 id:string;version:string;model:string;providers:readonly string[];
 tokenParameter:'max_tokens'|'max_completion_tokens';reasoningEffort:'low'|'high';
 maxOutputTokens:number;maxCalls:number;deadlineMs:number;reservation:number;
 inputPrice:number;outputPrice:number;temperature?:number;
}>;
export const selections:readonly Readonly<Selection>[]=Object.freeze((['everyday','expert'] as const).flatMap(stylistTier=>(['quick','deep'] as const).map(analysisDepth=>Object.freeze({stylistTier,analysisDepth}))));
export const analysisProfiles:readonly AnalysisProfile[]=Object.freeze(selections.map(s=>{
 const expert=s.stylistTier==='expert',deep=s.analysisDepth==='deep';
 return Object.freeze({...s,id:`${s.stylistTier}-${s.analysisDepth}`,version:'stylist-v1',model:expert?'anthropic/claude-opus-5':'openai/gpt-5.6-luna',providers:Object.freeze([expert?'google-vertex/global':'azure']),tokenParameter:expert?'max_tokens' as const:'max_completion_tokens' as const,reasoningEffort:deep?'high' as const:'low' as const,maxOutputTokens:deep?16384:8192,maxCalls:deep?6:2,deadlineMs:deep?180000:45000,reservation:expert?(deep?5000000:1200000):(deep?250000:100000),inputPrice:expert?0.000005:0.0000002,outputPrice:expert?0.000025:0.0000012});
}));
export function profileFor(selection:Selection,legacy=false):AnalysisProfile{
 const profile=analysisProfiles.find(p=>p.stylistTier===selection.stylistTier&&p.analysisDepth===selection.analysisDepth);
 if(!profile)throw new Error('Unknown analysis profile');
 if(!legacy)return profile;
 if(profile.id!=='everyday-quick')throw new Error('Legacy rollback supports Everyday Quick only');
 return Object.freeze({...profile,version:'stylist-legacy-v1',model:productionModel.id,providers:Object.freeze(['google-vertex/global']),tokenParameter:'max_tokens',reasoningEffort:'low',maxOutputTokens:productionModel.maxOutputTokens,maxCalls:2,deadlineMs:45000,reservation:100000,inputPrice:0.00000025,outputPrice:0.0000015,temperature:productionModel.temperature});
}
