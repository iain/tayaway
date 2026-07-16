import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import ExpenseSplit from './ExpenseSplit.vue'
import type { PoolMember, PoolExpense } from '@/types/pool'
import type {
  HydratedEvent,
  HydratedAttendance,
} from '@/composables/useHydratedEvent'

// vi.mock is hoisted, so the factory can only close over module-level state.
// We use these mutable variables and reassign them per-test.
let mockAttendances: HydratedAttendance[] = []
let mockExpenses: PoolExpense[] = []
let mockMembers: PoolMember[] = []
let mockParticipants: Array<{ id: string; userId: string; factor: number }> = []

vi.mock('@/stores/objectPool', () => ({
  useObjectPoolStore: () => ({
    getAll: (type: string) => {
      if (type === 'expense') return mockExpenses
      return []
    },
    get: (type: string, id: string) => {
      if (type === 'expenseParticipant')
        return mockParticipants.find((p) => p.id === id)
      return mockMembers.find((m) => m.id === id)
    },
    findBy: (_type: string, field: string, value: unknown) =>
      mockMembers.find(
        (m) => (m as unknown as Record<string, unknown>)[field] === value
      ),
  }),
}))

// ─── Helpers ────────────────────────────────────────────────────────────────

const BASE = {
  updatedAt: '2026-01-01T00:00:00.000Z',
  createdAt: '2026-01-01T00:00:00.000Z',
}

function mkEvent(overrides: Partial<HydratedEvent> = {}): HydratedEvent {
  return {
    ...BASE,
    id: 'event-1',
    objectType: 'event',
    name: 'Test Event',
    description: null,
    startDate: '2026-07-01',
    endDate: '2026-07-04',
    locationName: null,
    latitude: null,
    longitude: null,
    timezone: 'Europe/Amsterdam',
    workspaceId: 'ws-1',
    userId: 'member-1',
    datePollId: null,
    attendanceIds: [],
    workspace: undefined,
    member: undefined,
    datePoll: null,
    get attendances() {
      return mockAttendances
    },
    ...overrides,
  }
}

function mkAttendance(
  overrides: Partial<HydratedAttendance> = {}
): HydratedAttendance {
  const userId = overrides.userId ?? 'member-1'
  return {
    ...BASE,
    id: 'att-1',
    objectType: 'attendance',
    eventId: 'event-1',
    userId,
    guestId: null,
    hostUserId: null,
    status: 'going',
    days: null,
    createdByUserId: null,
    attendee: {
      name: 'Attendee',
      isGuest: false,
      billingUserId: userId,
      member: undefined,
      guest: undefined,
      hostMember: undefined,
    },
    ...overrides,
  }
}

function mkMember(overrides: Partial<PoolMember> = {}): PoolMember {
  return {
    ...BASE,
    id: 'member-1',
    objectType: 'member',
    workspaceId: 'ws-1',
    userId: 'member-1',
    email: 'alice@example.com',
    name: 'Alice',
    phoneNumber: null,
    birthday: null,
    locationName: null,
    latitude: null,
    longitude: null,
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
    userId: 'member-1',
    createdByUserId: null,
    settlementId: null,
    revertsExpenseId: null,
    description: 'Hotel',
    amount: 100,
    startDate: '2026-07-01',
    endDate: '2026-07-04',
    participantIds: [],
    ...overrides,
  }
}

function mountSplit(ev: HydratedEvent, total: number) {
  return mount(ExpenseSplit, { props: { event: ev, total } })
}

// ─── Tests ──────────────────────────────────────────────────────────────────

describe('ExpenseSplit', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    mockAttendances = []
    mockExpenses = []
    mockMembers = []
    mockParticipants = []
  })

  describe('visibility', () => {
    it('renders nothing when event has no dates', () => {
      const wrapper = mountSplit(mkEvent({ startDate: null, endDate: null }), 0)
      expect(wrapper.find('h2').exists()).toBe(false)
    })

    it('shows "No attendees yet" when there are no going attendances', () => {
      const wrapper = mountSplit(mkEvent(), 0)
      expect(wrapper.text()).toContain('No attendees yet')
    })

    it('shows "No attendees yet" when all attendances are declined', () => {
      mockAttendances = [mkAttendance({ status: 'declined' })]
      mockMembers = [mkMember()]
      const wrapper = mountSplit(mkEvent(), 0)
      expect(wrapper.text()).toContain('No attendees yet')
    })
  })

  describe('days calculation', () => {
    it('uses event dates when the attendance has no day set', () => {
      // Event Jul 1–4 = 4 days. Whole-event attendance → 4 days shown.
      mockAttendances = [mkAttendance()]
      mockMembers = [mkMember()]
      mockExpenses = [mkExpense({ amount: 90 })]
      const wrapper = mountSplit(
        mkEvent({ startDate: '2026-07-01', endDate: '2026-07-04' }),
        90
      )
      expect(wrapper.text()).toContain('4 days')
    })

    it('uses the attendance day set when present', () => {
      // Event Jul 1–4. Attendance Jul 1–2 = 2 days.
      mockAttendances = [mkAttendance({ days: ['2026-07-01', '2026-07-02'] })]
      mockMembers = [mkMember()]
      mockExpenses = [mkExpense({ amount: 90 })]
      const wrapper = mountSplit(
        mkEvent({ startDate: '2026-07-01', endDate: '2026-07-04' }),
        90
      )
      expect(wrapper.text()).toContain('2 days')
    })

    it('single-day attendance counts as 1 day', () => {
      mockAttendances = [mkAttendance({ days: ['2026-07-02'] })]
      mockMembers = [mkMember()]
      mockExpenses = [mkExpense({ amount: 50 })]
      const wrapper = mountSplit(
        mkEvent({ startDate: '2026-07-01', endDate: '2026-07-04' }),
        50
      )
      expect(wrapper.text()).toContain('1 day')
    })
  })

  describe('share and balance calculations', () => {
    it('single attendee who paid gets even balance', () => {
      mockAttendances = [mkAttendance()]
      mockMembers = [mkMember()]
      mockExpenses = [mkExpense({ amount: 60 })]
      const wrapper = mountSplit(mkEvent(), 60)
      expect(wrapper.text()).toContain('even')
    })

    it('payer is owed, non-payer owes', () => {
      // Alice pays €100; both attend full event, equal share → each €50.
      const ev = mkEvent({ startDate: '2026-07-01', endDate: '2026-07-05' })
      mockAttendances = [
        mkAttendance({ id: 'att-1', userId: 'member-1' }),
        mkAttendance({ id: 'att-2', userId: 'member-2' }),
      ]
      mockMembers = [
        mkMember({ id: 'member-1', name: 'Alice' }),
        mkMember({ id: 'member-2', userId: 'member-2', name: 'Bob' }),
      ]
      mockExpenses = [
        mkExpense({
          userId: 'member-1',
          amount: 100,
          startDate: ev.startDate!,
          endDate: ev.endDate!,
        }),
      ]
      const wrapper = mountSplit(ev, 100)
      expect(wrapper.text()).toContain('is owed €50.00')
      expect(wrapper.text()).toContain('owes €50.00')
    })

    it('partial attendee pays a proportionally smaller share', () => {
      // Event Jul 1–4 = 4 days. Alice: full (4). Bob: partial Jul 1–2 (2 days).
      // Expense covers full event. Alice overlap: 4, Bob overlap: 2, total: 6.
      // Alice: 4/6 * 60 = €40 share, Bob: 2/6 * 60 = €20 share.
      // Alice pays €60 → is owed €20. Bob pays €0 → owes €20.
      const ev = mkEvent({ startDate: '2026-07-01', endDate: '2026-07-04' })
      mockAttendances = [
        mkAttendance({ id: 'att-1', userId: 'member-1' }),
        mkAttendance({
          id: 'att-2',
          userId: 'member-2',
          days: ['2026-07-01', '2026-07-02'],
        }),
      ]
      mockMembers = [
        mkMember({ id: 'member-1', name: 'Alice' }),
        mkMember({ id: 'member-2', userId: 'member-2', name: 'Bob' }),
      ]
      mockExpenses = [
        mkExpense({
          userId: 'member-1',
          amount: 60,
          startDate: ev.startDate!,
          endDate: ev.endDate!,
        }),
      ]
      const wrapper = mountSplit(ev, 60)
      expect(wrapper.text()).toContain('is owed €20.00')
      expect(wrapper.text()).toContain('owes €20.00')
    })

    it('same-day expense is split among overlapping attendees', () => {
      // Event Jul 1–4. Alice: full. Bob: Jul 2–4. Expense: Jul 2 only.
      // Alice overlap: 1 day, Bob overlap: 1 day, total: 2.
      // Each share: 1/2 * 40 = €20.
      const ev = mkEvent({ startDate: '2026-07-01', endDate: '2026-07-04' })
      mockAttendances = [
        mkAttendance({ id: 'att-1', userId: 'member-1' }),
        mkAttendance({
          id: 'att-2',
          userId: 'member-2',
          days: ['2026-07-02', '2026-07-03', '2026-07-04'],
        }),
      ]
      mockMembers = [
        mkMember({ id: 'member-1', name: 'Alice' }),
        mkMember({ id: 'member-2', userId: 'member-2', name: 'Bob' }),
      ]
      mockExpenses = [
        mkExpense({
          userId: 'member-1',
          amount: 40,
          startDate: '2026-07-02',
          endDate: '2026-07-02',
        }),
      ]
      const wrapper = mountSplit(ev, 40)
      expect(wrapper.text()).toContain('is owed €20.00')
      expect(wrapper.text()).toContain('owes €20.00')
    })

    it('date-scoped expense only charges overlapping attendees', () => {
      // Event Jul 1–5. Alice: full. Bob: partial Jul 4–5 (2 days).
      // Expense covers Jul 1–3 (3 days).
      // Alice overlap with expense: 3 days, Bob overlap: 0 days.
      // Only Alice is charged the full €60.
      const ev = mkEvent({ startDate: '2026-07-01', endDate: '2026-07-05' })
      mockAttendances = [
        mkAttendance({ id: 'att-1', userId: 'member-1' }),
        mkAttendance({
          id: 'att-2',
          userId: 'member-2',
          days: ['2026-07-04', '2026-07-05'],
        }),
      ]
      mockMembers = [
        mkMember({ id: 'member-1', name: 'Alice' }),
        mkMember({ id: 'member-2', userId: 'member-2', name: 'Bob' }),
      ]
      mockExpenses = [
        mkExpense({
          userId: 'member-1',
          amount: 60,
          startDate: '2026-07-01',
          endDate: '2026-07-03',
        }),
      ]
      const wrapper = mountSplit(ev, 60)
      // Alice: share €60, paid €60 → even
      // Bob: share €0, paid €0 → even
      const text = wrapper.text()
      expect(text.match(/even/g)?.length).toBe(2)
    })

    it('bills a going guest to their host', () => {
      // Event Jul 1–2 = 2 days. Alice attends with one guest, Bob alone.
      // Head-days: Alice 2 + guest 2 = 4, Bob 2 → total 6.
      // Expense €60 → Alice's row (with guest) €40, Bob €20.
      const ev = mkEvent({ startDate: '2026-07-01', endDate: '2026-07-02' })
      mockAttendances = [
        mkAttendance({ id: 'att-1', userId: 'member-1' }),
        mkAttendance({ id: 'att-2', userId: 'member-2' }),
        mkAttendance({
          id: 'att-3',
          userId: null,
          guestId: 'guest-1',
          hostUserId: 'member-1',
          attendee: {
            name: 'Milo',
            isGuest: true,
            billingUserId: 'member-1',
            member: undefined,
            guest: undefined,
            hostMember: undefined,
          },
        }),
      ]
      mockMembers = [
        mkMember({ id: 'member-1', name: 'Alice' }),
        mkMember({ id: 'member-2', userId: 'member-2', name: 'Bob' }),
      ]
      mockExpenses = [
        mkExpense({
          userId: 'member-1',
          amount: 60,
          startDate: ev.startDate!,
          endDate: ev.endDate!,
        }),
      ]
      const wrapper = mountSplit(ev, 60)
      // Alice paid €60 against a €40 share → is owed €20; Bob owes €20.
      expect(wrapper.text()).toContain('is owed €20.00')
      expect(wrapper.text()).toContain('owes €20.00')
    })

    it('falls back to email when member name is null', () => {
      mockAttendances = [mkAttendance()]
      mockMembers = [mkMember({ name: null, email: 'alice@example.com' })]
      mockExpenses = []
      const wrapper = mountSplit(mkEvent(), 0)
      expect(wrapper.text()).toContain('alice@example.com')
    })
  })

  describe('specific-people', () => {
    it('weights specific-people shares by participant factor', () => {
      mockMembers = [
        mkMember({ id: 'm-alice', userId: 'alice', name: 'Alice' }),
        mkMember({ id: 'm-bob', userId: 'bob', name: 'Bob' }),
      ]
      mockAttendances = [
        mkAttendance({ id: 'att-a', userId: 'alice' }),
        mkAttendance({ id: 'att-b', userId: 'bob' }),
      ]
      mockParticipants = [
        { id: 'p-alice', userId: 'alice', factor: 2 },
        { id: 'p-bob', userId: 'bob', factor: 1 },
      ]
      const expense: PoolExpense = {
        ...BASE,
        id: 'e1',
        objectType: 'expense',
        eventId: 'event-1',
        userId: 'alice',
        createdByUserId: null,
        settlementId: null,
        revertsExpenseId: null,
        description: 'Dinner',
        amount: 30,
        startDate: '2026-07-01',
        endDate: '2026-07-01',
        participantIds: ['p-alice', 'p-bob'],
      }
      mockExpenses = [expense]

      const wrapper = mount(ExpenseSplit, {
        props: { event: mkEvent(), total: 30 },
      })
      const text = wrapper.text()
      expect(text).toContain('Alice')
      expect(text).toContain('Bob')
      // Alice factor 2, Bob factor 1 → Alice €20.00, Bob €10.00
      expect(text).toContain('€20.00')
      expect(text).toContain('€10.00')
    })
  })

  describe('guest itemization', () => {
    it('itemizes a guest as their own row under the host, with days but no money', () => {
      // Event Jul 1–4 = 4 days. Alice full, her guest Emma 2 days, Bob full.
      const ev = mkEvent({ startDate: '2026-07-01', endDate: '2026-07-04' })
      mockAttendances = [
        mkAttendance({ id: 'att-1', userId: 'member-1' }),
        mkAttendance({ id: 'att-2', userId: 'member-2' }),
        mkAttendance({
          id: 'att-3',
          userId: null,
          guestId: 'guest-1',
          hostUserId: 'member-1',
          days: ['2026-07-01', '2026-07-02'],
          attendee: {
            name: 'Emma',
            isGuest: true,
            billingUserId: 'member-1',
            member: undefined,
            guest: undefined,
            hostMember: undefined,
          },
        }),
      ]
      mockMembers = [
        mkMember({ id: 'member-1', name: 'Alice' }),
        mkMember({ id: 'member-2', userId: 'member-2', name: 'Bob' }),
      ]
      mockExpenses = []
      const wrapper = mountSplit(ev, 0)

      const guestRow = wrapper.find('[data-testid="split-guest-row"]')
      expect(guestRow.exists()).toBe(true)
      expect(guestRow.text()).toContain('Emma')
      expect(guestRow.text()).toContain('guest of Alice')
      expect(guestRow.text()).toContain('2 days')
      // Money stays on the host's row — the guest's cells are em-dashed.
      expect(guestRow.text().match(/—/g)?.length).toBe(3)

      // The mislabeled guest-day counter is gone; the total is head-days.
      expect(wrapper.text()).not.toContain('+1 guest')
      expect(wrapper.text()).not.toContain('+2 guests')
      expect(wrapper.text()).toContain('10 days')
    })
  })

  describe('totals row', () => {
    it('shows summed days across all attendees', () => {
      // Two full attendees on a 4-day event (Jul 1–4) → 8 total days
      const ev = mkEvent({ startDate: '2026-07-01', endDate: '2026-07-04' })
      mockAttendances = [
        mkAttendance({ id: 'att-1', userId: 'member-1' }),
        mkAttendance({ id: 'att-2', userId: 'member-2' }),
      ]
      mockMembers = [
        mkMember({ id: 'member-1', name: 'Alice' }),
        mkMember({ id: 'member-2', userId: 'member-2', name: 'Bob' }),
      ]
      mockExpenses = []
      const wrapper = mountSplit(ev, 60)
      expect(wrapper.text()).toContain('8 days')
    })
  })
})
