import { describe, it, expect, beforeEach } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useObjectPoolStore } from '@/stores/objectPool'
import type { ObjectTypeMap } from '@/types/pool'

// Helpers to build minimal pool objects
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
    revertsExpenseId: null,
    description: 'Test expense',
    amount: 10,
    startDate: '2026-01-01',
    endDate: '2026-01-01',
    participantIds: [],
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
    previousSettlementId: null,
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
    amount: 5,
    paidAt: null,
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  }
}

/**
 * These tests verify the O(n) precomputed map logic extracted from HomePage.vue.
 * Each test mirrors a computed property in the component.
 */
describe('HomePage computed maps', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  describe('attendeeCountByEvent', () => {
    it('counts attending RSVPs per event, excluding non-attending', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeRsvp({ id: 'r1', eventId: 'evt-1', attending: true }),
        makeRsvp({ id: 'r2', eventId: 'evt-1', attending: true }),
        makeRsvp({ id: 'r3', eventId: 'evt-1', attending: false }),
        makeRsvp({ id: 'r4', eventId: 'evt-2', attending: true }),
      ])

      // Replicate the HomePage attendeeCountByEvent logic
      const counts = new Map<string, number>()
      for (const r of pool.getAll('rsvp')) {
        if (r.attending) {
          counts.set(r.eventId, (counts.get(r.eventId) ?? 0) + 1)
        }
      }

      expect(counts.get('evt-1')).toBe(2)
      expect(counts.get('evt-2')).toBe(1)
      expect(counts.get('evt-3')).toBeUndefined()
    })
  })

  describe('unsettledExpenseCountByEvent', () => {
    it('counts expenses without a settlement, keyed by event', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeExpense({ id: 'exp-1', eventId: 'evt-1', settlementId: null }),
        makeExpense({ id: 'exp-2', eventId: 'evt-1', settlementId: null }),
        makeExpense({
          id: 'exp-3',
          eventId: 'evt-1',
          settlementId: 'settlement-1',
        }),
        makeExpense({ id: 'exp-4', eventId: 'evt-2', settlementId: null }),
      ])

      const counts = new Map<string, number>()
      for (const e of pool.getAll('expense')) {
        if (!e.settlementId) {
          counts.set(e.eventId, (counts.get(e.eventId) ?? 0) + 1)
        }
      }

      expect(counts.get('evt-1')).toBe(2)
      expect(counts.get('evt-2')).toBe(1)
      expect(counts.get('evt-3')).toBeUndefined()
    })
  })

  describe('unpaidTransferCountByEvent', () => {
    it('counts unpaid transfers per event via settlement join', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeSettlement({ id: 's1', eventId: 'evt-1' }),
        makeSettlement({ id: 's2', eventId: 'evt-2' }),
        makeTransfer({
          id: 't1',
          settlementId: 's1',
          paidAt: null,
        }),
        makeTransfer({
          id: 't2',
          settlementId: 's1',
          paidAt: '2026-01-02T00:00:00.000Z',
        }),
        makeTransfer({
          id: 't3',
          settlementId: 's2',
          paidAt: null,
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
          if (eventId) {
            counts.set(eventId, (counts.get(eventId) ?? 0) + 1)
          }
        }
      }

      expect(counts.get('evt-1')).toBe(1)
      expect(counts.get('evt-2')).toBe(1)
      expect(counts.get('evt-3')).toBeUndefined()
    })

    it('ignores transfers whose settlement is not in the pool', () => {
      const pool = useObjectPoolStore()
      pool.importObjects([
        makeTransfer({ id: 't1', settlementId: 'missing-settlement' }),
      ])

      const eventBySettlement = new Map<string, string>()
      for (const s of pool.getAll('settlement')) {
        eventBySettlement.set(s.id, s.eventId)
      }
      const counts = new Map<string, number>()
      for (const t of pool.getAll('settlementTransfer')) {
        if (!t.paidAt) {
          const eventId = eventBySettlement.get(t.settlementId)
          if (eventId) {
            counts.set(eventId, (counts.get(eventId) ?? 0) + 1)
          }
        }
      }

      expect(counts.size).toBe(0)
    })
  })
})
