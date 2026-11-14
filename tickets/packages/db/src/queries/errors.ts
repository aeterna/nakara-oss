export type TicketErrorCode =
  | 'limit'
  | 'blocked'
  | 'not_found'
  | 'invalid_transition'
  | 'not_claimer'
  | 'target_required';

export class TicketError extends Error {
  readonly code: TicketErrorCode;

  constructor(code: TicketErrorCode, message?: string) {
    super(message ?? code);
    this.name = 'TicketError';
    this.code = code;
  }
}
