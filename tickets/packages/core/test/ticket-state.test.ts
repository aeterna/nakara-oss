import { describe, it, expect } from 'vitest';
import { nextState, type TicketStatus, type Transition } from '../src/ticket-state.js';

describe('ticket state transitions acceptance tests', () => {
  it('allows every valid transition according to ticket lifecycle rules', () => {
    // 1. open -> claim by actor (open -> claimed, claimer=actor)
    const claimRes = nextState({ status: 'open', claimerId: null }, 'claim', 'user_staff_1');
    expect(claimRes).toEqual({
      ok: true,
      status: 'claimed',
      claimerId: 'user_staff_1',
    });

    // 2. claimed -> unclaim by claimer (claimed -> open, claimer=null)
    const unclaimRes = nextState({ status: 'claimed', claimerId: 'user_staff_1' }, 'unclaim', 'user_staff_1');
    expect(unclaimRes).toEqual({
      ok: true,
      status: 'open',
      claimerId: null,
    });

    // 3. claimed -> transfer by claimer to targetId (claimed -> claimed, claimer=targetId)
    const transferRes = nextState(
      { status: 'claimed', claimerId: 'user_staff_1' },
      'transfer',
      'user_staff_1',
      'user_staff_2',
    );
    expect(transferRes).toEqual({
      ok: true,
      status: 'claimed',
      claimerId: 'user_staff_2',
    });

    // 4. open -> close (open -> closed, claimer kept as null)
    const closeFromOpenRes = nextState({ status: 'open', claimerId: null }, 'close', 'user_actor');
    expect(closeFromOpenRes).toEqual({
      ok: true,
      status: 'closed',
      claimerId: null,
    });

    // 5. claimed -> close (claimed -> closed, claimer kept)
    const closeFromClaimedRes = nextState(
      { status: 'claimed', claimerId: 'user_staff_1' },
      'close',
      'user_actor',
    );
    expect(closeFromClaimedRes).toEqual({
      ok: true,
      status: 'closed',
      claimerId: 'user_staff_1',
    });

    // 6. closed -> reopen (closed -> open, claimer=null)
    const reopenRes = nextState({ status: 'closed', claimerId: 'user_staff_1' }, 'reopen', 'user_actor');
    expect(reopenRes).toEqual({
      ok: true,
      status: 'open',
      claimerId: null,
    });
  });

  it('refuses invalid transitions with the correct reason (table of refused transitions)', () => {
    const refusedCases: Array<{
      desc: string;
      cur: { status: TicketStatus; claimerId: string | null };
      transition: Transition;
      actorId: string;
      targetId?: string;
      expectedReason: 'invalid_transition' | 'not_claimer' | 'target_required';
    }> = [
      // 1. Cannot unclaim an open ticket
      {
        desc: 'unclaim on open ticket',
        cur: { status: 'open', claimerId: null },
        transition: 'unclaim',
        actorId: 'user_1',
        expectedReason: 'invalid_transition',
      },
      // 2. Cannot transfer an open ticket
      {
        desc: 'transfer on open ticket',
        cur: { status: 'open', claimerId: null },
        transition: 'transfer',
        actorId: 'user_1',
        targetId: 'user_2',
        expectedReason: 'invalid_transition',
      },
      // 3. Cannot reopen an open ticket
      {
        desc: 'reopen on open ticket',
        cur: { status: 'open', claimerId: null },
        transition: 'reopen',
        actorId: 'user_1',
        expectedReason: 'invalid_transition',
      },
      // 4. Cannot claim an already claimed ticket
      {
        desc: 'claim on already claimed ticket',
        cur: { status: 'claimed', claimerId: 'user_1' },
        transition: 'claim',
        actorId: 'user_2',
        expectedReason: 'invalid_transition',
      },
      // 5. Cannot reopen a claimed ticket
      {
        desc: 'reopen on claimed ticket',
        cur: { status: 'claimed', claimerId: 'user_1' },
        transition: 'reopen',
        actorId: 'user_1',
        expectedReason: 'invalid_transition',
      },
      // 6. Only claimer can unclaim
      {
        desc: 'unclaim by non-claimer',
        cur: { status: 'claimed', claimerId: 'user_1' },
        transition: 'unclaim',
        actorId: 'user_2',
        expectedReason: 'not_claimer',
      },
      // 7. Only claimer can transfer
      {
        desc: 'transfer by non-claimer',
        cur: { status: 'claimed', claimerId: 'user_1' },
        transition: 'transfer',
        actorId: 'user_2',
        targetId: 'user_3',
        expectedReason: 'not_claimer',
      },
      // 8. Transfer requires targetId
      {
        desc: 'transfer without targetId',
        cur: { status: 'claimed', claimerId: 'user_1' },
        transition: 'transfer',
        actorId: 'user_1',
        targetId: undefined,
        expectedReason: 'target_required',
      },
      // 9. Cannot claim a closed ticket
      {
        desc: 'claim on closed ticket',
        cur: { status: 'closed', claimerId: null },
        transition: 'claim',
        actorId: 'user_1',
        expectedReason: 'invalid_transition',
      },
      // 10. Cannot unclaim a closed ticket
      {
        desc: 'unclaim on closed ticket',
        cur: { status: 'closed', claimerId: 'user_1' },
        transition: 'unclaim',
        actorId: 'user_1',
        expectedReason: 'invalid_transition',
      },
      // 11. Cannot transfer a closed ticket
      {
        desc: 'transfer on closed ticket',
        cur: { status: 'closed', claimerId: 'user_1' },
        transition: 'transfer',
        actorId: 'user_1',
        targetId: 'user_2',
        expectedReason: 'invalid_transition',
      },
      // 12. Cannot close an already closed ticket
      {
        desc: 'close on already closed ticket',
        cur: { status: 'closed', claimerId: null },
        transition: 'close',
        actorId: 'user_1',
        expectedReason: 'invalid_transition',
      },
    ];

    expect(refusedCases.length).toBeGreaterThanOrEqual(8);

    for (const testCase of refusedCases) {
      const res = nextState(testCase.cur, testCase.transition, testCase.actorId, testCase.targetId);
      expect(res, `Failed for case: ${testCase.desc}`).toEqual({
        ok: false,
        reason: testCase.expectedReason,
      });
    }
  });
});
