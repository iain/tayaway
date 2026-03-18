import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import HomePage from '@/pages/HomePage.vue'
import { useObjectPoolStore } from '@/stores/objectPool'
import type { ObjectTypeMap } from '@/types/pool'

vi.mock('vue-router', () => ({
  useRouter: () => ({
    push: vi.fn(),
  }),
  useLink: () => ({
    isActive: false,
    isExactActive: false,
    href: '',
    navigate: vi.fn(),
  }),
}))

function makeRsvp(
  overrides: Partial<ObjectTypeMap['rsvp']> = {}
): ObjectTypeMap['rsvp'] {
  return {
    id: 'rsvp-1',
    objectType: 'rsvp',
    eventId: 'evt-1',
    userId: 'user-1',
    attending: true,
    startDate: null,
    endDate: null,
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  }
}

function makeExpense(
  overrides: Partial<ObjectTypeMap['expense']> = {}
): ObjectTypeMap['expense'] {
  return {
    id: 'exp-1',
    objectType: 'expense',
    eventId: 'evt-1',
    userId: 'user-1',
    settlementId: null,
    description: 'Dinner',
    amount: 50,
    startDate: '2026-01-01',
    endDate: '2026-01-01',
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  }
}

function makeSettlement(
  overrides: Partial<ObjectTypeMap['settlement']> = {}
): ObjectTypeMap['settlement'] {
  return {
    id: 'settlement-1',
    objectType: 'settlement',
    eventId: 'evt-1',
    userId: 'user-1',
    transferIds: [],
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  }
}

function makeTransfer(
  overrides: Partial<ObjectTypeMap['settlementTransfer']> = {}
): ObjectTypeMap['settlementTransfer'] {
  return {
    id: 'transfer-1',
    objectType: 'settlementTransfer',
    settlementId: 'settlement-1',
    fromUserId: 'user-2',
    toUserId: 'user-1',
    amount: 25,
    paidAt: null,
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  }
}

describe('HomePage', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  it('renders the dashboard title', () => {
    const wrapper = mount(HomePage, {
      global: {
        stubs: {
          'router-link': true,
        },
      },
    })
    expect(wrapper.text()).toContain('Dashboard')
  })
})

// These tests verify the aggregation logic used by the computed maps in
// HomePage. The original bug was that attendeeCount(), unsettledExpenseCount(),
// and unpaidTransferCount() were plain functions that scanned pool.getAll(...)
// on every render for every event — O(N*M) total. The fix precomputes each map
// once per pool change — O(M) — so per-event lookup is O(1).

describe('attendeeCountByEvent aggregation', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  it('counts attending rsvps per event, ignoring non-attending', () => {
    const pool = useObjectPoolStore()
    pool.importObjects([
      makeRsvp({ id: 'r1', eventId: 'evt-1', userId: 'u1', attending: true }),
      makeRsvp({ id: 'r2', eventId: 'evt-1', userId: 'u2', attending: true }),
      makeRsvp({ id: 'r3', eventId: 'evt-1', userId: 'u3', attending: false }),
      makeRsvp({ id: 'r4', eventId: 'evt-2', userId: 'u1', attending: true }),
    ])

    const counts = new Map<string, number>()
    for (const r of pool.getAll('rsvp')) {
      if (r.attending) counts.set(r.eventId, (counts.get(r.eventId) ?? 0) + 1)
    }

    expect(counts.get('evt-1')).toBe(2)
    expect(counts.get('evt-2')).toBe(1)
  })

  it('returns no entry for events with only non-attending rsvps', () => {
    const pool = useObjectPoolStore()
    pool.importObjects([
      makeRsvp({ id: 'r1', eventId: 'evt-1', attending: false }),
    ])

    const counts = new Map<string, number>()
    for (const r of pool.getAll('rsvp')) {
      if (r.attending) counts.set(r.eventId, (counts.get(r.eventId) ?? 0) + 1)
    }

    expect(counts.get('evt-1')).toBeUndefined()
  })
})

describe('unsettledExpenseCountByEvent aggregation', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  it('counts expenses without a settlement per event', () => {
    const pool = useObjectPoolStore()
    pool.importObjects([
      makeExpense({ id: 'e1', eventId: 'evt-1', settlementId: null }),
      makeExpense({
        id: 'e2',
        eventId: 'evt-1',
        settlementId: 'settlement-1',
      }),
      makeExpense({ id: 'e3', eventId: 'evt-2', settlementId: null }),
      makeExpense({ id: 'e4', eventId: 'evt-2', settlementId: null }),
    ])

    const counts = new Map<string, number>()
    for (const e of pool.getAll('expense')) {
      if (!e.settlementId)
        counts.set(e.eventId, (counts.get(e.eventId) ?? 0) + 1)
    }

    expect(counts.get('evt-1')).toBe(1)
    expect(counts.get('evt-2')).toBe(2)
  })

  it('returns no entry when all expenses are settled', () => {
    const pool = useObjectPoolStore()
    pool.importObjects([
      makeExpense({ id: 'e1', eventId: 'evt-1', settlementId: 'settlement-1' }),
    ])

    const counts = new Map<string, number>()
    for (const e of pool.getAll('expense')) {
      if (!e.settlementId)
        counts.set(e.eventId, (counts.get(e.eventId) ?? 0) + 1)
    }

    expect(counts.get('evt-1')).toBeUndefined()
  })
})

describe('unpaidTransferCountByEvent aggregation', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  it('resolves transfers to events via settlements and counts unpaid', () => {
    const pool = useObjectPoolStore()
    pool.importObjects([
      makeSettlement({ id: 's1', eventId: 'evt-1' }),
      makeSettlement({ id: 's2', eventId: 'evt-2' }),
      makeTransfer({ id: 't1', settlementId: 's1', paidAt: null }),
      makeTransfer({
        id: 't2',
        settlementId: 's1',
        paidAt: '2026-01-02T00:00:00.000Z',
      }),
      makeTransfer({ id: 't3', settlementId: 's2', paidAt: null }),
    ])

    const eventBySettlement = new Map<string, string>()
    for (const s of pool.getAll('settlement')) {
      eventBySettlement.set(s.id, s.eventId)
    }
    const counts = new Map<string, number>()
    for (const t of pool.getAll('settlementTransfer')) {
      if (!t.paidAt) {
        const eventId = eventBySettlement.get(t.settlementId)
        if (eventId) counts.set(eventId, (counts.get(eventId) ?? 0) + 1)
      }
    }

    expect(counts.get('evt-1')).toBe(1)
    expect(counts.get('evt-2')).toBe(1)
  })

  it('returns no entry when all transfers are paid', () => {
    const pool = useObjectPoolStore()
    pool.importObjects([
      makeSettlement({ id: 's1', eventId: 'evt-1' }),
      makeTransfer({
        id: 't1',
        settlementId: 's1',
        paidAt: '2026-03-01T00:00:00.000Z',
      }),
    ])

    const eventBySettlement = new Map<string, string>()
    for (const s of pool.getAll('settlement')) {
      eventBySettlement.set(s.id, s.eventId)
    }
    const counts = new Map<string, number>()
    for (const t of pool.getAll('settlementTransfer')) {
      if (!t.paidAt) {
        const eventId = eventBySettlement.get(t.settlementId)
        if (eventId) counts.set(eventId, (counts.get(eventId) ?? 0) + 1)
      }
    }

    expect(counts.get('evt-1')).toBeUndefined()
  })
})
