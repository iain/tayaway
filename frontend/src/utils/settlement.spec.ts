import { describe, it, expect } from 'vitest'
import {
  computeBalances,
  deriveBalancesFromTransfers,
  minimizeTransfers,
} from './settlement'

describe('computeBalances', () => {
  const eventStart = '2026-07-01'
  const eventEnd = '2026-07-07'

  it('returns empty map when single payer is sole attendee', () => {
    const expenses = [
      {
        userId: 'alice',
        startDate: eventStart,
        endDate: eventEnd,
        amount: 100,
      },
    ]
    const rsvps = [{ userId: 'alice', startDate: null, endDate: null }]

    const balances = computeBalances(expenses, rsvps, eventStart, eventEnd)
    expect(balances.size).toBe(0)
  })

  it('splits evenly between two equal attendees with one payer', () => {
    const expenses = [
      {
        userId: 'alice',
        startDate: eventStart,
        endDate: eventEnd,
        amount: 100,
      },
    ]
    const rsvps = [
      { userId: 'alice', startDate: null, endDate: null },
      { userId: 'bob', startDate: null, endDate: null },
    ]

    const balances = computeBalances(expenses, rsvps, eventStart, eventEnd)
    // Alice paid 100, share is 50 → balance = 50 - 100 = -50 (owed)
    expect(balances.get('alice')).toBe(-50)
    // Bob paid 0, share is 50 → balance = 50 - 0 = 50 (owes)
    expect(balances.get('bob')).toBe(50)
  })

  it('splits proportionally by attendance overlap', () => {
    // Event: Jul 1-4 (4 days)
    const start = '2026-07-01'
    const end = '2026-07-04'
    const expenses = [
      { userId: 'alice', startDate: start, endDate: end, amount: 60 },
    ]
    const rsvps = [
      { userId: 'alice', startDate: start, endDate: end }, // 4 days
      { userId: 'bob', startDate: start, endDate: '2026-07-02' }, // 2 days
    ]

    const balances = computeBalances(expenses, rsvps, start, end)
    // Total overlap days: 4 + 2 = 6
    // Alice share: 4/6 * 60 = 40, paid 60 → balance = -20 (owed)
    expect(balances.get('alice')).toBe(-20)
    // Bob share: 2/6 * 60 = 20, paid 0 → balance = 20 (owes)
    expect(balances.get('bob')).toBe(20)
  })

  it('ignores expenses with no RSVP overlap', () => {
    const expenses = [
      {
        userId: 'alice',
        startDate: '2026-07-10',
        endDate: '2026-07-12',
        amount: 100,
      },
    ]
    const rsvps = [
      { userId: 'alice', startDate: eventStart, endDate: '2026-07-03' },
      { userId: 'bob', startDate: eventStart, endDate: '2026-07-03' },
    ]

    const balances = computeBalances(expenses, rsvps, eventStart, eventEnd)
    // No overlap with expense dates → alice paid 100 but has 0 share
    // Only paid_by_user is populated, so alice balance = 0 - 100 = -100
    expect(balances.get('alice')).toBe(-100)
    expect(balances.has('bob')).toBe(false)
  })

  it('accumulates multiple expenses', () => {
    const expenses = [
      { userId: 'alice', startDate: eventStart, endDate: eventEnd, amount: 60 },
      { userId: 'bob', startDate: eventStart, endDate: eventEnd, amount: 40 },
    ]
    const rsvps = [
      { userId: 'alice', startDate: null, endDate: null },
      { userId: 'bob', startDate: null, endDate: null },
    ]

    const balances = computeBalances(expenses, rsvps, eventStart, eventEnd)
    // Alice: share 50 (half of 100), paid 60 → -10 (owed)
    expect(balances.get('alice')).toBe(-10)
    // Bob: share 50, paid 40 → 10 (owes)
    expect(balances.get('bob')).toBe(10)
  })

  it('filters out near-zero balances', () => {
    const expenses = [
      {
        userId: 'alice',
        startDate: eventStart,
        endDate: eventEnd,
        amount: 10.0,
      },
    ]
    const rsvps = [
      { userId: 'alice', startDate: null, endDate: null },
      { userId: 'bob', startDate: null, endDate: null },
    ]

    // Alice share 5, paid 10 → -5; Bob share 5, paid 0 → 5
    const balances = computeBalances(expenses, rsvps, eventStart, eventEnd)
    expect(balances.size).toBe(2)
    // Both are well above 0.005 threshold
    expect(balances.get('alice')).toBe(-5)
    expect(balances.get('bob')).toBe(5)
  })

  describe('with explicit participants', () => {
    const resolver = (pid: string) => {
      const map: Record<string, { userId: string; factor: number }> = {
        'p-alice': { userId: 'alice', factor: 1 },
        'p-bob': { userId: 'bob', factor: 1 },
        'p-carol': { userId: 'carol', factor: 1 },
      }
      return map[pid]
    }

    it('splits equally among explicit participants', () => {
      const expenses = [
        {
          userId: 'alice',
          startDate: eventStart,
          endDate: eventEnd,
          amount: 90,
          participantIds: ['p-bob', 'p-carol'],
        },
      ]
      const rsvps = [
        { userId: 'alice', startDate: null, endDate: null },
        { userId: 'bob', startDate: null, endDate: null },
        { userId: 'carol', startDate: null, endDate: null },
      ]

      const balances = computeBalances(
        expenses,
        rsvps,
        eventStart,
        eventEnd,
        resolver
      )
      // Bob and Carol each owe 45 (90/2). Alice paid 90, owes 0.
      expect(balances.get('alice')).toBe(-90)
      expect(balances.get('bob')).toBe(45)
      expect(balances.get('carol')).toBe(45)
    })

    it('handles creator excluded from participants', () => {
      const expenses = [
        {
          userId: 'alice',
          startDate: eventStart,
          endDate: eventEnd,
          amount: 30,
          participantIds: ['p-bob'],
        },
      ]
      const rsvps = [
        { userId: 'alice', startDate: null, endDate: null },
        { userId: 'bob', startDate: null, endDate: null },
      ]

      const balances = computeBalances(
        expenses,
        rsvps,
        eventStart,
        eventEnd,
        resolver
      )
      // Bob owes 30, Alice paid 30. Bob→Alice 30
      expect(balances.get('alice')).toBe(-30)
      expect(balances.get('bob')).toBe(30)
    })

    it('handles mixed expenses: some with participants, some without', () => {
      const expenses = [
        // No participants → RSVP overlap split
        {
          userId: 'alice',
          startDate: eventStart,
          endDate: eventEnd,
          amount: 30,
        },
        // With participants → equal split between alice and bob
        {
          userId: 'bob',
          startDate: eventStart,
          endDate: eventEnd,
          amount: 20,
          participantIds: ['p-alice', 'p-bob'],
        },
      ]
      const rsvps = [
        { userId: 'alice', startDate: null, endDate: null },
        { userId: 'bob', startDate: null, endDate: null },
        { userId: 'carol', startDate: null, endDate: null },
      ]

      const balances = computeBalances(
        expenses,
        rsvps,
        eventStart,
        eventEnd,
        resolver
      )
      // Expense 1: 30 / 3 = 10 each → alice=10, bob=10, carol=10
      // Expense 2: 20 / 2 = 10 each → alice=10, bob=10
      // Total shares: alice=20, bob=20, carol=10
      // Paid: alice=30, bob=20
      // Balances: alice=20-30=-10, bob=20-20=0, carol=10-0=10
      expect(balances.get('alice')).toBe(-10)
      expect(balances.has('bob')).toBe(false) // 0, filtered out
      expect(balances.get('carol')).toBe(10)
    })

    it('weights shares by participant factor', () => {
      // Alice paid 30, participants Alice:1 + Bob:2 → Alice owes 10, Bob owes 20
      const factorResolver = (pid: string) => {
        const map: Record<string, { userId: string; factor: number }> = {
          'p-alice': { userId: 'alice', factor: 1 },
          'p-bob': { userId: 'bob', factor: 2 },
        }
        return map[pid]
      }
      const expenses = [
        {
          userId: 'alice',
          startDate: eventStart,
          endDate: eventEnd,
          amount: 30,
          participantIds: ['p-alice', 'p-bob'],
        },
      ]
      const rsvps = [
        { userId: 'alice', startDate: null, endDate: null },
        { userId: 'bob', startDate: null, endDate: null },
      ]

      const balances = computeBalances(
        expenses,
        rsvps,
        eventStart,
        eventEnd,
        factorResolver
      )
      // Alice share = 1/3 * 30 = 10; paid 30 → balance = -20 (owed 20)
      // Bob share = 2/3 * 30 = 20; paid 0 → balance = 20 (owes 20)
      expect(balances.get('alice')).toBe(-20)
      expect(balances.get('bob')).toBe(20)
    })

    it('falls back to RSVP overlap when no resolver provided', () => {
      const expenses = [
        {
          userId: 'alice',
          startDate: eventStart,
          endDate: eventEnd,
          amount: 100,
          participantIds: ['p-bob'],
        },
      ]
      const rsvps = [
        { userId: 'alice', startDate: null, endDate: null },
        { userId: 'bob', startDate: null, endDate: null },
      ]

      // Without resolver, participantIds are ignored → normal RSVP split
      const balances = computeBalances(expenses, rsvps, eventStart, eventEnd)
      expect(balances.get('alice')).toBe(-50)
      expect(balances.get('bob')).toBe(50)
    })
  })
})

describe('minimizeTransfers', () => {
  it('returns empty array for empty balances', () => {
    expect(minimizeTransfers(new Map())).toEqual([])
  })

  it('creates single transfer between two users', () => {
    const balances = new Map([
      ['alice', -50], // owed 50
      ['bob', 50], // owes 50
    ])

    const transfers = minimizeTransfers(balances)
    expect(transfers).toEqual([
      { fromUserId: 'bob', toUserId: 'alice', amount: 50 },
    ])
  })

  it('handles one debtor and two creditors', () => {
    const balances = new Map([
      ['alice', -30],
      ['bob', -20],
      ['charlie', 50],
    ])

    const transfers = minimizeTransfers(balances)
    expect(transfers).toHaveLength(2)
    // Charlie owes 50 total: 30 to alice, 20 to bob
    expect(transfers[0]).toEqual({
      fromUserId: 'charlie',
      toUserId: 'alice',
      amount: 30,
    })
    expect(transfers[1]).toEqual({
      fromUserId: 'charlie',
      toUserId: 'bob',
      amount: 20,
    })
  })

  it('handles two debtors and one creditor', () => {
    const balances = new Map([
      ['alice', -50],
      ['bob', 30],
      ['charlie', 20],
    ])

    const transfers = minimizeTransfers(balances)
    expect(transfers).toHaveLength(2)
    expect(transfers[0]).toEqual({
      fromUserId: 'bob',
      toUserId: 'alice',
      amount: 30,
    })
    expect(transfers[1]).toEqual({
      fromUserId: 'charlie',
      toUserId: 'alice',
      amount: 20,
    })
  })

  it('returns empty array when all balances are below threshold', () => {
    const balances = new Map([
      ['alice', 0.003],
      ['bob', -0.003],
    ])

    expect(minimizeTransfers(balances)).toEqual([])
  })

  it('rounds transfer amounts to 2 decimal places', () => {
    const balances = new Map([
      ['alice', -33.33],
      ['bob', 33.33],
    ])

    const transfers = minimizeTransfers(balances)
    expect(transfers[0]!.amount).toBe(33.33)
  })
})

describe('deriveBalancesFromTransfers', () => {
  it('returns empty map for empty transfer list', () => {
    expect(deriveBalancesFromTransfers([])).toEqual(new Map())
  })

  it('produces equal and opposite balances for a single transfer', () => {
    const balances = deriveBalancesFromTransfers([
      { fromUserId: 'bob', toUserId: 'alice', amount: 50 },
    ])
    expect(balances.get('bob')).toBe(50)
    expect(balances.get('alice')).toBe(-50)
  })

  it('sums balances across multiple transfers', () => {
    const balances = deriveBalancesFromTransfers([
      { fromUserId: 'bob', toUserId: 'dave', amount: 40 },
      { fromUserId: 'carol', toUserId: 'alice', amount: 30 },
    ])
    expect(balances.get('alice')).toBe(-30)
    expect(balances.get('bob')).toBe(40)
    expect(balances.get('carol')).toBe(30)
    expect(balances.get('dave')).toBe(-40)
  })

  it('accumulates when the same user appears in several transfers', () => {
    const balances = deriveBalancesFromTransfers([
      { fromUserId: 'charlie', toUserId: 'alice', amount: 30 },
      { fromUserId: 'charlie', toUserId: 'bob', amount: 20 },
    ])
    expect(balances.get('charlie')).toBe(50)
    expect(balances.get('alice')).toBe(-30)
    expect(balances.get('bob')).toBe(-20)
  })

  it('round-trips with computeBalances + minimizeTransfers', () => {
    const start = '2026-07-01'
    const end = '2026-07-07'
    const expenses = [
      { userId: 'alice', startDate: start, endDate: end, amount: 60 },
      { userId: 'bob', startDate: start, endDate: end, amount: 60 },
    ]
    const rsvps = [
      { userId: 'alice', startDate: null, endDate: null },
      { userId: 'bob', startDate: null, endDate: null },
      { userId: 'carol', startDate: null, endDate: null },
    ]
    const original = computeBalances(expenses, rsvps, start, end)
    const transfers = minimizeTransfers(original)
    const derived = deriveBalancesFromTransfers(transfers)

    for (const [userId, amount] of original) {
      expect(derived.get(userId) ?? 0).toBeCloseTo(amount, 2)
    }
  })

  it('handles null fromUserId or toUserId by skipping that side', () => {
    const balances = deriveBalancesFromTransfers([
      { fromUserId: null, toUserId: 'alice', amount: 10 },
      { fromUserId: 'bob', toUserId: null, amount: 5 },
    ])
    expect(balances.get('alice')).toBe(-10)
    expect(balances.get('bob')).toBe(5)
  })
})
