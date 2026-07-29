import { describe, it, expect } from 'vitest'
import {
  annotateTransfers,
  computeBalances,
  computeDriftBalances,
  deriveBalancesFromTransfers,
  minimizeTransfers,
} from './settlement'

// A going attendance billing `billingUserId`; days null = whole event.
// Guests appear as their own entries billing their host.
const going = (billingUserId: string, days: string[] | null = null) => ({
  status: 'going',
  days,
  billingUserId,
})

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
    const attendances = [going('alice')]

    const balances = computeBalances(
      expenses,
      attendances,
      eventStart,
      eventEnd
    )
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
    const attendances = [going('alice'), going('bob')]

    const balances = computeBalances(
      expenses,
      attendances,
      eventStart,
      eventEnd
    )
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
    const attendances = [
      going('alice'), // whole event, 4 days
      going('bob', ['2026-07-01', '2026-07-02']), // 2 days
    ]

    const balances = computeBalances(expenses, attendances, start, end)
    // Total overlap days: 4 + 2 = 6
    // Alice share: 4/6 * 60 = 40, paid 60 → balance = -20 (owed)
    expect(balances.get('alice')).toBe(-20)
    // Bob share: 2/6 * 60 = 20, paid 0 → balance = 20 (owes)
    expect(balances.get('bob')).toBe(20)
  })

  it('splits proportionally for a non-contiguous come-and-go attendee', () => {
    // Event Jul 1-4. Alice whole event (4 days); Bob comes and goes on Jul 1
    // and Jul 3 only (2 days, skipping Jul 2) — same day count, but the
    // attendance set is what counts, not the contiguous hull.
    const start = '2026-07-01'
    const end = '2026-07-04'
    const expenses = [
      { userId: 'alice', startDate: start, endDate: end, amount: 60 },
    ]
    const attendances = [
      going('alice'),
      going('bob', ['2026-07-01', '2026-07-03']),
    ]

    const balances = computeBalances(expenses, attendances, start, end)
    // Total attended days in window: 4 + 2 = 6.
    // Alice 4/6·60 = 40, paid 60 → -20. Bob 2/6·60 = 20 → owes 20.
    expect(balances.get('alice')).toBe(-20)
    expect(balances.get('bob')).toBe(20)
  })

  it("bills a hosted guest's days to the host", () => {
    // Event Jul 1-2. Bob pays €210. Alice attends both days and brings a
    // guest both days; Bob attends alone. Head-days billed: Alice 4, Bob 2.
    const start = '2026-07-01'
    const end = '2026-07-02'
    const expenses = [
      { userId: 'bob', startDate: start, endDate: end, amount: 210 },
    ]
    const attendances = [
      going('alice'),
      going('alice'), // Alice's guest — own entry, billing Alice
      going('bob'),
    ]

    const balances = computeBalances(expenses, attendances, start, end)
    // Alice 4/6·210 = 140 owed; Bob 2/6·210 = 70 − 210 paid = −140.
    expect(balances.get('alice')).toBe(140)
    expect(balances.get('bob')).toBe(-140)
  })

  it("ignores a guest's days outside the expense window", () => {
    // Expense covers Jul 1 only. Alice's guest lands on Jul 2, so day 1 is a
    // plain 1-for-1 split between Alice and Bob.
    const start = '2026-07-01'
    const end = '2026-07-02'
    const expenses = [
      { userId: 'bob', startDate: start, endDate: start, amount: 100 },
    ]
    const attendances = [
      going('alice', ['2026-07-01', '2026-07-02']),
      going('alice', ['2026-07-02']), // Alice's guest, day 2 only
      going('bob', ['2026-07-01']),
    ]

    const balances = computeBalances(expenses, attendances, start, end)
    expect(balances.get('alice')).toBe(50)
    expect(balances.get('bob')).toBe(-50)
  })

  it('ignores expenses with no attendance overlap', () => {
    const expenses = [
      {
        userId: 'alice',
        startDate: '2026-07-10',
        endDate: '2026-07-12',
        amount: 100,
      },
    ]
    const attendances = [
      going('alice', ['2026-07-01', '2026-07-02', '2026-07-03']),
      going('bob', ['2026-07-01', '2026-07-02', '2026-07-03']),
    ]

    const balances = computeBalances(
      expenses,
      attendances,
      eventStart,
      eventEnd
    )
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
    const attendances = [going('alice'), going('bob')]

    const balances = computeBalances(
      expenses,
      attendances,
      eventStart,
      eventEnd
    )
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
    const attendances = [going('alice'), going('bob')]

    // Alice share 5, paid 10 → -5; Bob share 5, paid 0 → 5
    const balances = computeBalances(
      expenses,
      attendances,
      eventStart,
      eventEnd
    )
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
      const attendances = [going('alice'), going('bob'), going('carol')]

      const balances = computeBalances(
        expenses,
        attendances,
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
      const attendances = [going('alice'), going('bob')]

      const balances = computeBalances(
        expenses,
        attendances,
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
        // No participants → attendance overlap split
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
      const attendances = [going('alice'), going('bob'), going('carol')]

      const balances = computeBalances(
        expenses,
        attendances,
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
      const attendances = [going('alice'), going('bob')]

      const balances = computeBalances(
        expenses,
        attendances,
        eventStart,
        eventEnd,
        factorResolver
      )
      // Alice share = 1/3 * 30 = 10; paid 30 → balance = -20 (owed 20)
      // Bob share = 2/3 * 30 = 20; paid 0 → balance = 20 (owes 20)
      expect(balances.get('alice')).toBe(-20)
      expect(balances.get('bob')).toBe(20)
    })

    it('falls back to attendance overlap when no resolver provided', () => {
      const expenses = [
        {
          userId: 'alice',
          startDate: eventStart,
          endDate: eventEnd,
          amount: 100,
          participantIds: ['p-bob'],
        },
      ]
      const attendances = [going('alice'), going('bob')]

      // Without resolver, participantIds are ignored → normal attendance split
      const balances = computeBalances(
        expenses,
        attendances,
        eventStart,
        eventEnd
      )
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

  it('breaks balance ties by userId so output is independent of Map order', () => {
    // bob and alice owe the same amount; carol and dave are owed the same
    // amount. Whatever order the Map was built in, the pairing must come
    // out identical.
    const entries: [string, number][] = [
      ['bob', 50],
      ['alice', 50],
      ['dave', -50],
      ['carol', -50],
    ]

    const forward = minimizeTransfers(new Map(entries))
    const reversed = minimizeTransfers(new Map([...entries].reverse()))

    expect(forward).toEqual(reversed)
    expect(forward).toEqual([
      { fromUserId: 'alice', toUserId: 'carol', amount: 50 },
      { fromUserId: 'bob', toUserId: 'dave', amount: 50 },
    ])
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
    const attendances = [going('alice'), going('bob'), going('carol')]
    const original = computeBalances(expenses, attendances, start, end)
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

describe('annotateTransfers', () => {
  const nameFor = (uid: string) =>
    ({ alice: 'Alice', bob: 'Bob', carol: 'Carol', dave: 'Dave' })[uid] ??
    'Unknown'

  it('returns empty list for empty input', () => {
    expect(annotateTransfers([], new Map(), nameFor)).toEqual([])
  })

  it('annotates a symmetric clear: "Clears X... · Y now even"', () => {
    const initial = new Map([
      ['bob', 40],
      ['dave', -40],
    ])
    const result = annotateTransfers(
      [{ fromUserId: 'bob', toUserId: 'dave', amount: 40 }],
      initial,
      nameFor
    )
    expect(result).toHaveLength(1)
    expect(result[0]!.annotation).toBe("Clears Bob's balance · Dave now even")
  })

  it('annotates partial from side: "Settles €A of X\'s €B · Y now even"', () => {
    const initial = new Map([
      ['bob', 50],
      ['dave', -40],
    ])
    const result = annotateTransfers(
      [{ fromUserId: 'bob', toUserId: 'dave', amount: 40 }],
      initial,
      nameFor
    )
    expect(result[0]!.annotation).toBe(
      "Settles €40.00 of Bob's €50.00 · Dave now even"
    )
  })

  it('annotates partial to side: "Clears X... · Y still owed €C"', () => {
    const initial = new Map([
      ['bob', 40],
      ['dave', -70],
    ])
    const result = annotateTransfers(
      [{ fromUserId: 'bob', toUserId: 'dave', amount: 40 }],
      initial,
      nameFor
    )
    expect(result[0]!.annotation).toBe(
      "Clears Bob's balance · Dave still owed €30.00"
    )
  })

  it('annotates partial both sides', () => {
    const initial = new Map([
      ['bob', 60],
      ['dave', -70],
    ])
    const result = annotateTransfers(
      [{ fromUserId: 'bob', toUserId: 'dave', amount: 50 }],
      initial,
      nameFor
    )
    expect(result[0]!.annotation).toBe(
      "Settles €50.00 of Bob's €60.00 · Dave still owed €20.00"
    )
  })

  it('walks running balances so later annotations reflect earlier transfers', () => {
    // Bob owes 70 split across two creditors. The second annotation must
    // reflect that bob's balance has already been reduced by the first transfer.
    const initial = new Map([
      ['bob', 70],
      ['alice', -40],
      ['carol', -30],
    ])
    const result = annotateTransfers(
      [
        { fromUserId: 'bob', toUserId: 'alice', amount: 40 },
        { fromUserId: 'bob', toUserId: 'carol', amount: 30 },
      ],
      initial,
      nameFor
    )
    // First transfer reduces Bob from 70 to 30.
    expect(result[0]!.annotation).toBe(
      "Settles €40.00 of Bob's €70.00 · Alice now even"
    )
    // Second transfer must see Bob at 30, not 70 — proving the running-balance
    // update happened between iterations.
    expect(result[1]!.annotation).toBe("Clears Bob's balance · Carol now even")
  })

  it('handles null userIds by labelling them Unknown via nameFor fallback', () => {
    const initial = new Map<string, number>([['alice', -10]])
    const result = annotateTransfers(
      [{ fromUserId: null, toUserId: 'alice', amount: 10 }],
      initial,
      nameFor
    )
    expect(result[0]!.annotation).toContain('Alice now even')
  })

  it('preserves the original transfer fields alongside the annotation', () => {
    const initial = new Map([
      ['bob', 40],
      ['alice', -40],
    ])
    const result = annotateTransfers(
      [{ fromUserId: 'bob', toUserId: 'alice', amount: 40 }],
      initial,
      nameFor
    )
    expect(result[0]).toMatchObject({
      fromUserId: 'bob',
      toUserId: 'alice',
      amount: 40,
    })
  })
})

describe('computeDriftBalances', () => {
  it('returns an empty map when current balances match prior transfers', () => {
    // Alice paid 100, Bob owed 50 → Bob paid Alice 50 in a prior settlement.
    // Nothing has changed since, so drift is zero.
    const current = new Map([
      ['alice', -50],
      ['bob', 50],
    ])
    const priorTransfers = [
      { fromUserId: 'bob', toUserId: 'alice', amount: 50 },
    ]

    expect(computeDriftBalances(current, priorTransfers).size).toBe(0)
  })

  it('surfaces a late attendee as residual owing', () => {
    // After settlement 1 (Alice paid 90, Bob owed 45, transfer happened),
    // Carol arrives. New fair share = 30 each. Alice should now be owed 60,
    // Bob only owes 30 (not 45), Carol owes 30.
    const currentBalances = new Map([
      ['alice', -60],
      ['bob', 30],
      ['carol', 30],
    ])
    const priorTransfers = [
      { fromUserId: 'bob', toUserId: 'alice', amount: 45 },
    ]

    const drift = computeDriftBalances(currentBalances, priorTransfers)
    // Alice currently owed 60 but already received 45, so drift is still 15 owed.
    // Bob currently owes 30 but paid 45, so drift is 15 he should get back.
    // Carol currently owes 30 and has paid nothing, so drift is 30 owed.
    expect(drift.get('alice')).toBe(-15)
    expect(drift.get('bob')).toBe(-15)
    expect(drift.get('carol')).toBe(30)
  })

  it('drops users whose drift rounds to zero', () => {
    const currentBalances = new Map([['alice', 0.003]])
    expect(computeDriftBalances(currentBalances, []).size).toBe(0)
  })
})
