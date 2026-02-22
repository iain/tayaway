import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import ExpenseSplit from './ExpenseSplit.vue'
import type { PoolEvent, PoolRsvp, PoolMember, PoolExpense } from '@/types/pool'

// vi.mock is hoisted, so the factory can only close over module-level state.
// We use these mutable variables and reassign them per-test.
let mockRsvps: PoolRsvp[] = []
let mockExpenses: PoolExpense[] = []
let mockMembers: PoolMember[] = []

vi.mock('@/stores/objectPool', () => ({
  useObjectPoolStore: () => ({
    getAll: (type: string) => {
      if (type === 'rsvp') return mockRsvps
      if (type === 'expense') return mockExpenses
      return []
    },
    get: (_type: string, id: string) => mockMembers.find((m) => m.id === id),
  }),
}))

// ─── Helpers ────────────────────────────────────────────────────────────────

const BASE = {
  updatedAt: '2026-01-01T00:00:00.000Z',
  createdAt: '2026-01-01T00:00:00.000Z',
}

function mkEvent(overrides: Partial<PoolEvent> = {}): PoolEvent {
  return {
    ...BASE,
    id: 'event-1',
    objectType: 'event',
    name: 'Test Event',
    description: null,
    startDate: '2026-07-01',
    endDate: '2026-07-04',
    workspaceId: 'ws-1',
    memberId: 'member-1',
    datePollId: null,
    rsvpIds: [],
    ...overrides,
  }
}

function mkRsvp(overrides: Partial<PoolRsvp> = {}): PoolRsvp {
  return {
    ...BASE,
    id: 'rsvp-1',
    objectType: 'rsvp',
    eventId: 'event-1',
    memberId: 'member-1',
    attending: true,
    startDate: null,
    endDate: null,
    ...overrides,
  }
}

function mkMember(overrides: Partial<PoolMember> = {}): PoolMember {
  return {
    ...BASE,
    id: 'member-1',
    objectType: 'member',
    workspaceId: 'ws-1',
    email: 'alice@example.com',
    name: 'Alice',
    role: 'member',
    ...overrides,
  }
}

function mkExpense(overrides: Partial<PoolExpense> = {}): PoolExpense {
  return {
    ...BASE,
    id: 'expense-1',
    objectType: 'expense',
    eventId: 'event-1',
    memberId: 'member-1',
    description: 'Hotel',
    amount: 100,
    ...overrides,
  }
}

function mountSplit(ev: PoolEvent, total: number) {
  return mount(ExpenseSplit, { props: { event: ev, total } })
}

// ─── Tests ──────────────────────────────────────────────────────────────────

describe('ExpenseSplit', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    mockRsvps = []
    mockExpenses = []
    mockMembers = []
  })

  describe('visibility', () => {
    it('renders nothing when event has no dates', () => {
      const wrapper = mountSplit(mkEvent({ startDate: null, endDate: null }), 0)
      expect(wrapper.find('h2').exists()).toBe(false)
    })

    it('shows "No attendees yet" when there are no attending RSVPs', () => {
      const wrapper = mountSplit(mkEvent(), 0)
      expect(wrapper.text()).toContain('No attendees yet')
    })

    it('shows "No attendees yet" when all RSVPs are not attending', () => {
      mockRsvps = [mkRsvp({ attending: false })]
      mockMembers = [mkMember()]
      const wrapper = mountSplit(mkEvent(), 0)
      expect(wrapper.text()).toContain('No attendees yet')
    })
  })

  describe('nights calculation', () => {
    it('uses event dates when RSVP has no partial dates', () => {
      // Event Jul 1–4 = 3 nights. RSVP has no partial dates → 3 nights shown.
      mockRsvps = [mkRsvp()]
      mockMembers = [mkMember()]
      mockExpenses = [mkExpense({ amount: 90 })]
      const wrapper = mountSplit(
        mkEvent({ startDate: '2026-07-01', endDate: '2026-07-04' }),
        90
      )
      expect(wrapper.text()).toContain('3 nights')
    })

    it('uses RSVP partial dates when set', () => {
      // Event Jul 1–4 = 3 nights, RSVP Jul 1–2 = 1 night.
      mockRsvps = [mkRsvp({ startDate: '2026-07-01', endDate: '2026-07-02' })]
      mockMembers = [mkMember()]
      mockExpenses = [mkExpense({ amount: 90 })]
      const wrapper = mountSplit(
        mkEvent({ startDate: '2026-07-01', endDate: '2026-07-04' }),
        90
      )
      expect(wrapper.text()).toContain('1 night')
    })
  })

  describe('share and balance calculations', () => {
    it('single attendee who paid gets 100% and settled balance', () => {
      mockRsvps = [mkRsvp()]
      mockMembers = [mkMember()]
      mockExpenses = [mkExpense({ amount: 60 })]
      const wrapper = mountSplit(mkEvent(), 60)
      expect(wrapper.text()).toContain('100%')
      expect(wrapper.text()).toContain('settled')
    })

    it('two full attendees each get 50%', () => {
      mockRsvps = [
        mkRsvp({ id: 'rsvp-1', memberId: 'member-1' }),
        mkRsvp({ id: 'rsvp-2', memberId: 'member-2' }),
      ]
      mockMembers = [
        mkMember({ id: 'member-1', name: 'Alice' }),
        mkMember({ id: 'member-2', name: 'Bob' }),
      ]
      mockExpenses = [mkExpense({ memberId: 'member-1', amount: 100 })]
      const wrapper = mountSplit(
        mkEvent({ startDate: '2026-07-01', endDate: '2026-07-05' }),
        100
      )
      const text = wrapper.text()
      expect(text.match(/50%/g)?.length).toBeGreaterThanOrEqual(2)
    })

    it('payer is owed, non-payer owes', () => {
      // Alice pays €100; each owes €50. Alice is owed €50, Bob owes €50.
      mockRsvps = [
        mkRsvp({ id: 'rsvp-1', memberId: 'member-1' }),
        mkRsvp({ id: 'rsvp-2', memberId: 'member-2' }),
      ]
      mockMembers = [
        mkMember({ id: 'member-1', name: 'Alice' }),
        mkMember({ id: 'member-2', name: 'Bob' }),
      ]
      mockExpenses = [mkExpense({ memberId: 'member-1', amount: 100 })]
      const wrapper = mountSplit(
        mkEvent({ startDate: '2026-07-01', endDate: '2026-07-05' }),
        100
      )
      expect(wrapper.text()).toContain('owed €50.00')
      expect(wrapper.text()).toContain('owes €50.00')
    })

    it('partial attendee pays a proportionally smaller share', () => {
      // Event Jul 1–5 = 4 nights. Alice: full (4). Bob: partial Jul 1–2 (1).
      // Total nights: 5. Alice 80% = €40 share, Bob 20% = €10 share.
      // Alice pays €50 → owed €10. Bob pays €0 → owes €10.
      mockRsvps = [
        mkRsvp({ id: 'rsvp-1', memberId: 'member-1' }),
        mkRsvp({
          id: 'rsvp-2',
          memberId: 'member-2',
          startDate: '2026-07-01',
          endDate: '2026-07-02',
        }),
      ]
      mockMembers = [
        mkMember({ id: 'member-1', name: 'Alice' }),
        mkMember({ id: 'member-2', name: 'Bob' }),
      ]
      mockExpenses = [mkExpense({ memberId: 'member-1', amount: 50 })]
      const wrapper = mountSplit(
        mkEvent({ startDate: '2026-07-01', endDate: '2026-07-05' }),
        50
      )
      expect(wrapper.text()).toContain('80%')
      expect(wrapper.text()).toContain('20%')
      expect(wrapper.text()).toContain('owed €10.00')
      expect(wrapper.text()).toContain('owes €10.00')
    })

    it('falls back to email when member name is null', () => {
      mockRsvps = [mkRsvp()]
      mockMembers = [mkMember({ name: null, email: 'alice@example.com' })]
      mockExpenses = []
      const wrapper = mountSplit(mkEvent(), 0)
      expect(wrapper.text()).toContain('alice@example.com')
    })
  })

  describe('totals row', () => {
    it('shows summed nights across all attendees', () => {
      // Two full attendees on a 3-night event → 6 total nights
      mockRsvps = [
        mkRsvp({ id: 'rsvp-1', memberId: 'member-1' }),
        mkRsvp({ id: 'rsvp-2', memberId: 'member-2' }),
      ]
      mockMembers = [
        mkMember({ id: 'member-1', name: 'Alice' }),
        mkMember({ id: 'member-2', name: 'Bob' }),
      ]
      mockExpenses = []
      const wrapper = mountSplit(
        mkEvent({ startDate: '2026-07-01', endDate: '2026-07-04' }),
        60
      )
      expect(wrapper.text()).toContain('6 nights')
    })
  })
})
