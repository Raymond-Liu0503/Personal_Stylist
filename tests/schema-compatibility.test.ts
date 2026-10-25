import test from 'node:test';
import assert from 'node:assert/strict';
import {outputJsonSchema,swapAttributes} from '../supabase/functions/_shared/agents/model-schema.ts';

test('nullable suggestion enum uses provider-compatible typed branches',()=>{
 const schema=outputJsonSchema.properties.suggestions.items.properties.targetAttribute;
 assert.deepEqual(schema,{anyOf:[{type:'string',enum:swapAttributes},{type:'null'}]});
});
