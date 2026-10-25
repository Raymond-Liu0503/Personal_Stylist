import type {AnalysisProfile} from '../agents/model-config.ts';
import type {Provider} from './types.ts';
import {ApiError} from '../security/errors.ts';
import {sanitizeJpeg} from '../security/input.ts';
// Activation requires documented provider-specific verification of this ceiling
// for a single sanitized <=1600px JPEG. It is NOT inferred from compressed size.
export const IMAGE_TOKEN_CEILING=16384;
export const INPUT_TOKEN_CEILING=65536;
export function assertInputBound(input:Parameters<Provider['generate']>[0]){
 if(input.tools.length)throw new ApiError('INVALID_INPUT',400,'Tools are not supported for outfit analysis.');
 if(input.image)sanitizeJpeg(input.image);
 // UTF-8 bytes conservatively bound text tokens for the approved byte-token models.
 // Include schemas, all repair/review messages and additional framing headroom.
 const textBytes=new TextEncoder().encode(JSON.stringify({messages:input.messages,schema:input.schema})).length;
 if(textBytes+4096+(input.image?IMAGE_TOKEN_CEILING:0)>INPUT_TOKEN_CEILING)throw new ApiError('INVALID_INPUT',400,'This assessment exceeds the safe input budget. Shorten your styling brief.');
}
export function assertReservation(profile:AnalysisProfile){
 const bound=Math.ceil(profile.maxCalls*(INPUT_TOKEN_CEILING*profile.inputPrice+profile.maxOutputTokens*profile.outputPrice)*1e6);
 if(bound>profile.reservation)throw new ApiError('DISABLED',503,'The analysis budget configuration could not be verified.');
}
