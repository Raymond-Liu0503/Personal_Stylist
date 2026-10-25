import type { ErrorCode } from '../../../../packages/contracts/src/index.ts';
export class ApiError extends Error {
  constructor(public code:ErrorCode, public status=400, message='The request could not be completed.') { super(message); }
}
