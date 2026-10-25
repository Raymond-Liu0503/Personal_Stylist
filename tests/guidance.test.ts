import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {validateKnowledge} from '../scripts/compile-skills.mjs';
const catalogue=()=>JSON.parse(readFileSync('supabase/functions/_shared/skills/knowledge.json','utf8'));
test('compiler rejects oversized complete responses, duplicates and dangling sources',()=>{
 const large=catalogue();large.entries[0].text='界'.repeat(2000);assert.throws(()=>validateKnowledge(large),/budget/);
 const duplicate=catalogue();duplicate.entries.push(duplicate.entries[0]);assert.throws(()=>validateKnowledge(duplicate),/Duplicate/);
 const dangling=catalogue();dangling.entries[0].sourceIds=['missing'];assert.throws(()=>validateKnowledge(dangling),/source/);
 assert.equal(validateKnowledge(catalogue()).entries.length,11);
});
