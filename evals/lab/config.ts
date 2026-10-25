import { z } from 'zod';
import { MetadataSchema } from '../../packages/contracts/src/index.ts';
import { productionModel } from '../../supabase/functions/_shared/agents/model-config.ts';
export const models=[productionModel.id,'google/gemini-3.1-pro-preview','anthropic/claude-opus-4.6'] as const;
const id=z.string().regex(/^[a-zA-Z0-9_-]{1,80}$/);
export const ModelSettings=z.object({model:z.enum(models),route:z.string().min(1).max(100),maxOutputTokens:z.number().int().min(500).max(8000),temperature:z.number().min(0).max(2),reasoningEffort:z.enum(['minimal','low','medium','high'])}).strict();
export const ExperimentSchema=z.object({id,split:z.enum(['development','heldout']),pipeline:z.enum(['baseline','generator','review','deep']),generator:ModelSettings,evidence:ModelSettings,styling:ModelSettings,generatorPrompt:id.default('outfit-v1'),criticPrompt:id.default('review-v1'),seed:id,sourceExperiment:id.optional(),sourceRound:z.number().int().min(0).max(1).default(0)}).strict();
export type Experiment=z.infer<typeof ExperimentSchema>;
export const DatasetSchema=z.object({schemaVersion:z.literal(1),mockOnly:z.boolean().default(false),cases:z.array(z.object({id,group:id,split:z.enum(['development','heldout']),image:z.string().min(1),rights:z.string().min(1).refine(s=>!s.includes('REPLACE')),metadata:MetadataSchema,recentTechniques:z.array(z.string()).max(9).default([])}).strict()).min(1)}).strict().superRefine((v,ctx)=>{
 const groups=new Map<string,string>();const ids=new Set<string>();
 for(const c of v.cases){if(ids.has(c.id))ctx.addIssue({code:'custom',message:'Duplicate case ID'});ids.add(c.id);if(groups.has(c.group)&&groups.get(c.group)!==c.split)ctx.addIssue({code:'custom',message:'Related photos must stay in the same split'});groups.set(c.group,c.split);}
 for(const [split,max] of [['development',12],['heldout',18]] as const)if([...groups.values()].filter(s=>s===split).length>max)ctx.addIssue({code:'custom',message:`At most ${max} ${split} groups`});
});
export type Dataset=z.infer<typeof DatasetSchema>;
export const PreferenceSchema=z.object({pair:id,choice:z.enum(['A','B','tie','neither']),reasons:z.string().min(1).max(4000)}).strict();
export const LabelSchema=z.object({attempt:id,round:z.number().int().min(0).max(1),candidate:id,revision:z.number().int().positive(),useful:z.boolean(),groundingError:z.boolean(),constraintFailure:z.boolean(),redundant:z.boolean(),notes:z.string().max(4000)}).strict();
