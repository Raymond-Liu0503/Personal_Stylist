export type Message = {role:'system'|'user'|'assistant'|'tool';content:unknown;tool_calls?:ToolCall[];tool_call_id?:string};
export type ToolCall = {id:string;type:'function';function:{name:string;arguments:string}};
export type Usage = {inputTokens:number;outputTokens:number;costMicrodollars:number|null};
export type Generation = {output?:unknown;toolCalls?:ToolCall[];usage:Usage};
export type ReasoningEffort='minimal'|'low'|'medium'|'high';
export interface Provider {model:string;generate(input:{messages:Message[];image?:Uint8Array;tools:unknown[];schema:unknown;signal:AbortSignal;maxOutputTokens:number;temperature:number;reasoningEffort:ReasoningEffort}):Promise<Generation>}
