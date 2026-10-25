import { outfitSkill } from '../skills/bundle.ts';
import { productionModel } from './model-config.ts';
export interface SpecialistDefinition {id:string;version:string;inputSchemaVersion:number;outputSchemaVersion:number;skillBundle:typeof outfitSkill;toolNames:readonly string[];modelConfig:typeof productionModel;maxModelRounds:number;maxToolCalls:number}
export const outfit:SpecialistDefinition={id:'outfit',version:'5.0.0',inputSchemaVersion:1,outputSchemaVersion:1,skillBundle:outfitSkill,toolNames:[],modelConfig:productionModel,maxModelRounds:2,maxToolCalls:0};
export const registry:Readonly<Record<string,SpecialistDefinition>>=Object.freeze({outfit});

export const assessmentVersions=(model:string)=>({agent:outfit.version,skill:outfit.skillBundle.version,rubric:outfit.skillBundle.knowledge.rubricVersion,model});
