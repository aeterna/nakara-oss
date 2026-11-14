export type TicketStatus = 'open' | 'claimed' | 'closed';
export type Transition = 'claim' | 'unclaim' | 'transfer' | 'close' | 'reopen';

export type TransitionReason = 'invalid_transition' | 'not_claimer' | 'target_required';

export type NextStateResult =
  | { ok: true; status: TicketStatus; claimerId: string | null }
  | { ok: false; reason: TransitionReason };

export function nextState(
  cur: { status: TicketStatus; claimerId: string | null },
  t: Transition,
  actorId: string,
  targetId?: string,
): NextStateResult {
  switch (t) {
    case 'claim': {
      if (cur.status !== 'open') {
        return { ok: false, reason: 'invalid_transition' };
      }
      return { ok: true, status: 'claimed', claimerId: actorId };
    }
    case 'unclaim': {
      if (cur.status !== 'claimed') {
        return { ok: false, reason: 'invalid_transition' };
      }
      if (cur.claimerId !== actorId) {
        return { ok: false, reason: 'not_claimer' };
      }
      return { ok: true, status: 'open', claimerId: null };
    }
    case 'transfer': {
      if (cur.status !== 'claimed') {
        return { ok: false, reason: 'invalid_transition' };
      }
      if (cur.claimerId !== actorId) {
        return { ok: false, reason: 'not_claimer' };
      }
      if (!targetId || targetId.trim() === '') {
        return { ok: false, reason: 'target_required' };
      }
      return { ok: true, status: 'claimed', claimerId: targetId };
    }
    case 'close': {
      if (cur.status === 'closed') {
        return { ok: false, reason: 'invalid_transition' };
      }
      // from open | claimed -> closed (claimer kept)
      return { ok: true, status: 'closed', claimerId: cur.claimerId };
    }
    case 'reopen': {
      if (cur.status !== 'closed') {
        return { ok: false, reason: 'invalid_transition' };
      }
      return { ok: true, status: 'open', claimerId: null };
    }
    default: {
      return { ok: false, reason: 'invalid_transition' };
    }
  }
}
