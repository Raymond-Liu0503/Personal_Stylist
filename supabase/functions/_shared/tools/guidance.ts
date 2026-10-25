import { z } from 'zod';
import { outfitSkill } from '../skills/bundle.ts';
import { ApiError } from '../security/errors.ts';
export const guidanceTopics=outfitSkill.knowledge.entries.map(e=>e.topic) as [typeof outfitSkill.knowledge.entries[number]['topic'],...typeof outfitSkill.knowledge.entries[number]['topic'][]];
export const guidanceArgs = z.object({topic:z.enum(guidanceTopics)}).strict();
export const guidanceTool = {type:'function',function:{name:'lookup_clothing_guidance',description:'Reviewed additional clothing guidance',parameters:{type:'object',additionalProperties:false,properties:{topic:{type:'string',enum:guidanceTopics}},required:['topic']}}};
export function lookupGuidance(name:string,args:unknown) {
  if(name!=='lookup_clothing_guidance') throw new ApiError('INVALID_MODEL_OUTPUT',502);
  const parsed=guidanceArgs.safeParse(args);
  if(!parsed.success) throw new ApiError('INVALID_MODEL_OUTPUT',502);
  const entry=outfitSkill.knowledge.entries.find(e=>e.topic===parsed.data.topic)!;
  return JSON.stringify(entry);
}
