import {readFileSync} from 'node:fs';
const filename=process.argv[2];if(!filename)throw new Error('Usage: node evals/runner/gates.mjs /path/to/reviewed-results.json');
const {cases,privacyApproved,accountDeletionVerified,consentVerified,professionalReview}=JSON.parse(readFileSync(filename,'utf8'));
if(!Array.isArray(cases)||!cases.length)throw new Error('No evaluation cases supplied');
const fraction=fn=>cases.filter(fn).length/cases.length;
const latencies=cases.map(c=>c.latencyMs).sort((a,b)=>a-b);
const percentile=p=>latencies[Math.max(0,Math.ceil(p*latencies.length)-1)];
const gates={atLeast100DiverseCases:new Set(cases.map(c=>c.id)).size>=100,twoReviewersEveryCase:cases.every(c=>new Set(c.reviewers).size>=2),noInventedDetails:fraction(c=>c.noMaterialInvention===true)>=.9,actionableAdvice:fraction(c=>c.actionable===true)>=.8,stableScores:fraction(c=>Array.isArray(c.repeatedScores)&&c.repeatedScores.length>=2&&c.repeatedScores.every(Number.isFinite)&&Math.max(...c.repeatedScores)-Math.min(...c.repeatedScores)<=1)>=.9,noSeriousFailures:cases.every(c=>c.seriousFailure===false),medianUnder10Seconds:percentile(.5)<10000,p95Under25Seconds:percentile(.95)<25000,meanCostUnderOneCent:cases.reduce((n,c)=>n+c.costMicrodollars,0)/cases.length<10000,privacyApproved:privacyApproved===true,accountDeletionVerified:accountDeletionVerified===true,consentVerified:consentVerified===true,professionalReview:professionalReview===true};
console.log(JSON.stringify({passed:Object.values(gates).every(Boolean),gates},null,2));if(Object.values(gates).some(x=>!x))process.exitCode=1;
