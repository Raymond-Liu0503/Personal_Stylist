import { ApiError } from './errors.ts';
import { readLimited } from './input.ts';
// Apple's code exchange authenticates this fresh authorization to our app. Match its subject
// against the Apple identity already verified by Supabase before revoking the returned token.
export async function revokeAppleGrant(code:string,subject:string,config:{clientId:string;clientSecret:string},signal:AbortSignal,fetcher:typeof fetch=fetch) {
 const form=new URLSearchParams({client_id:config.clientId,client_secret:config.clientSecret,code,grant_type:'authorization_code'});
 const response=await fetcher('https://appleid.apple.com/auth/token',{method:'POST',body:form,signal});
 if(!response.ok){await response.body?.cancel();throw new ApiError('REAUTHENTICATION_REQUIRED',401,'Please authorise with Apple again to delete your account.');}
 let tokens;try{tokens=JSON.parse(new TextDecoder().decode(await readLimited(response.body,16000,signal)));}catch{throw new ApiError('DELETION_PENDING',503);}
 // Token was obtained directly from Apple's authenticated HTTPS endpoint, never accepted from client.
 let claims;try{const part=tokens.id_token.split('.')[1];claims=JSON.parse(atob(part.replace(/-/g,'+').replace(/_/g,'/')));}catch{throw new ApiError('REAUTHENTICATION_REQUIRED',401);}
 const now=Math.floor(Date.now()/1000);
 if(claims.iss!=='https://appleid.apple.com'||claims.aud!==config.clientId||claims.sub!==subject||claims.exp<=now||claims.iat<now-300||claims.iat>now+60||typeof tokens.access_token!=='string')throw new ApiError('REAUTHENTICATION_REQUIRED',401);
 const revoked=await fetcher('https://appleid.apple.com/auth/revoke',{method:'POST',signal,body:new URLSearchParams({client_id:config.clientId,client_secret:config.clientSecret,token:tokens.refresh_token??tokens.access_token,token_type_hint:tokens.refresh_token?'refresh_token':'access_token'})});
 await revoked.body?.cancel();if(!revoked.ok)throw new ApiError('DELETION_PENDING',503,'Apple revocation is pending. Please retry deletion with fresh Apple authorisation.');
}
