import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import SettlementSection from './SettlementSection.vue'
import type {
  PoolEvent,
  PoolExpense,
  PoolMember,
  PoolRsvp,
  PoolSettlement,
  PoolSettlementTransfer,
  PoolExpenseParticipant,
} from '@/types/pool'

let mockMembers: PoolMember[] = []
let mockRsvps: PoolRsvp[] = []
let mockExpenses: PoolExpense[] = []
let mockSettlements: PoolSettlement[] = []
let mockTransfers: PoolSettlementTransfer[] = []
let mockParticipants: PoolExpenseParticipant[] = []

vi.mock('@/stores/objectPool', () => ({
  useObjectPoolStore: () => ({
    getAll: (type: string) => {
      if (type === 'member') return mockMembers
      if (type === 'rsvp') return mockRsvps
      if (type === 'expense') return mockExpenses
      if (type === 'settlement') return mockSettlements
      if (type === 'settlementTransfer') return mockTransfers
      if (type === 'expenseParticipant') return mockParticipants
      return []
    },
    get: (type: string, id: string) => {
      if (type === 'expenseParticipant')
        return mockParticipants.find((p) => p.id === id)
      if (type === 'member') return mockMembers.find((m) => m.id === id)
      return undefined
    },
    findBy: (type: string, field: string, value: unknown) => {
      const list =
        type === 'member' ? mockMembers : type === 'rsvp' ? mockRsvps : []
      return list.find(
        (o) => (o as unknown as Record<string, unknown>)[field] === value
      )
    },
  }),
}))

vi.mock('@/stores/settlements', () => ({
  useSettlementsStore: () => ({
    createSettlement: vi.fn(),
    deleteSettlement: vi.fn(),
    markTransferPaid: vi.fn(),
  }),
}))

const BASE = {
  updatedAt: '2026-01-01T00:00:00.000Z',
  createdAt: '2026-01-01T00:00:00.000Z',
}

function mkEvent(overrides: Partial<PoolEvent> = {}): PoolEvent {
  return {
    ...BASE,
    id: 'event-1',
    objectType: 'event',
    name: 'Trip',
    description: null,
    startDate: '2026-07-01',
    endDate: '2026-07-05',
    locationName: null,
    latitude: null,
    longitude: null,
    timezone: 'Europe/Amsterdam',
    workspaceId: 'ws-1',
    userId: 'user-test',
    datePollId: null,
    rsvpIds: [],
    ...overrides,
  }
}

function mkMember(overrides: Partial<PoolMember> = {}): PoolMember {
  return {
    ...BASE,
    id: 'member-test',
    objectType: 'member',
    workspaceId: 'ws-1',
    userId: 'user-test',
    email: 'test@example.com',
    name: 'Test User',
    phoneNumber: null,
    birthday: null,
    locationName: null,
    latitude: null,
    longitude: null,
    role: 'member',
    ...overrides,
  }
}

function mkRsvp(overrides: Partial<PoolRsvp>): PoolRsvp {
  return {
    ...BASE,
    id: 'rsvp-x',
    objectType: 'rsvp',
    eventId: 'event-1',
    userId: 'user-x',
    createdByUserId: null,
    attending: true,
    attendance: null,
    startDate: null,
    endDate: null,
    ...overrides,
  }
}

function mkExpense(overrides: Partial<PoolExpense>): PoolExpense {
  return {
    ...BASE,
    id: 'exp-1',
    objectType: 'expense',
    eventId: 'event-1',
    userId: 'user-test',
    createdByUserId: null,
    settlementId: 'settle-1',
    revertsExpenseId: null,
    description: 'Hotel',
    amount: 200,
    startDate: '2026-07-01',
    endDate: '2026-07-05',
    participantIds: [],
    ...overrides,
  }
}

function mkSettlement(overrides: Partial<PoolSettlement>): PoolSettlement {
  return {
    ...BASE,
    id: 'settle-1',
    objectType: 'settlement',
    eventId: 'event-1',
    userId: 'user-test',
    previousSettlementId: null,
    transferIds: [],
    ...overrides,
  }
}

function mkTransfer(
  overrides: Partial<PoolSettlementTransfer>
): PoolSettlementTransfer {
  return {
    ...BASE,
    id: 'tr-1',
    objectType: 'settlementTransfer',
    settlementId: 'settle-1',
    fromUserId: 'user-x',
    toUserId: 'user-test',
    amount: 50,
    paidAt: null,
    paidByUserId: null,
    supersededAt: null,
    ...overrides,
  }
}

function mountSection(event: PoolEvent = mkEvent()) {
  return mount(SettlementSection, {
    props: { event, currentUserId: 'user-test' },
    global: {
      stubs: {
        teleport: true,
        BaseModal: {
          template: '<div><slot /></div>',
          props: ['open', 'title', 'size'],
        },
        EpcQrModal: { template: '<div />' },
        SettlementMath: { template: '<div />' },
        'router-link': { template: '<a><slot /></a>' },
      },
    },
  })
}

describe('SettlementSection drift detection', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    mockMembers = []
    mockRsvps = []
    mockExpenses = []
    mockSettlements = []
    mockTransfers = []
    mockParticipants = []
  })

  it('flags drift when an unaccounted RSVP changes the fair share', () => {
    // Same setup as the no-drift case, but Bob attends too. The single Alice
    // → Test User €100 transfer no longer covers Bob's share, so the banner
    // should appear.
    mockMembers = [
      mkMember(),
      mkMember({
        id: 'member-alice',
        userId: 'user-alice',
        email: 'alice@example.com',
        name: 'Alice',
      }),
      mkMember({
        id: 'member-bob',
        userId: 'user-bob',
        email: 'bob@example.com',
        name: 'Bob',
      }),
    ]
    mockRsvps = [
      mkRsvp({ id: 'rsvp-test', userId: 'user-test' }),
      mkRsvp({ id: 'rsvp-alice', userId: 'user-alice' }),
      mkRsvp({ id: 'rsvp-bob', userId: 'user-bob' }),
    ]
    mockExpenses = [mkExpense({ amount: 200 })]
    mockSettlements = [mkSettlement({})]
    mockTransfers = [
      mkTransfer({
        id: 'tr-1',
        fromUserId: 'user-alice',
        toUserId: 'user-test',
        amount: 100,
        paidAt: null,
      }),
    ]

    const wrapper = mountSection()

    expect(
      wrapper.find('[data-testid="settlement-drift-banner"]').exists()
    ).toBe(true)
  })

  it('does not flag drift when active transfers (paid or not) cover the current fair share', () => {
    // Two attendees on a 4-day trip. Test User paid €200, so each owes €100.
    // The settlement issued one transfer Alice → Test User of €100. It's
    // unpaid, but it already represents the right split — there's no drift.
    mockMembers = [
      mkMember(),
      mkMember({
        id: 'member-alice',
        userId: 'user-alice',
        email: 'alice@example.com',
        name: 'Alice',
      }),
    ]
    mockRsvps = [
      mkRsvp({ id: 'rsvp-test', userId: 'user-test' }),
      mkRsvp({ id: 'rsvp-alice', userId: 'user-alice' }),
    ]
    mockExpenses = [mkExpense({ amount: 200 })]
    mockSettlements = [mkSettlement({})]
    mockTransfers = [
      mkTransfer({
        id: 'tr-1',
        fromUserId: 'user-alice',
        toUserId: 'user-test',
        amount: 100,
        paidAt: null,
      }),
    ]

    const wrapper = mountSection()

    expect(
      wrapper.find('[data-testid="settlement-drift-banner"]').exists()
    ).toBe(false)
    expect(
      wrapper.find('[data-testid="start-settlement-button"]').exists()
    ).toBe(false)
  })

  it('does not flag drift on rounding crumbs that cannot fund a transfer', () => {
    // Mirrors a real situation: the latest top-up's transfers add up to the
    // right thing modulo cent rounding, leaving one user with a one-cent
    // residual that has no matching creditor. That's not real drift.
    //
    // Setup: weighted split where Charlie's factor (1.5) yields a non-round
    // share (94.2857…). After cents-rounding the balance and subtracting
    // the active transfers, three users net to zero and Charlie keeps a
    // +0.01 leftover with no creditor — minimizeTransfers returns nothing.
    mockMembers = [
      mkMember(),
      mkMember({
        id: 'member-alice',
        userId: 'user-alice',
        email: 'alice@example.com',
        name: 'Alice',
      }),
      mkMember({
        id: 'member-bob',
        userId: 'user-bob',
        email: 'bob@example.com',
        name: 'Bob',
      }),
      mkMember({
        id: 'member-charlie',
        userId: 'user-charlie',
        email: 'charlie@example.com',
        name: 'Charlie',
      }),
    ]
    mockRsvps = [
      mkRsvp({ id: 'rsvp-test', userId: 'user-test' }),
      mkRsvp({ id: 'rsvp-alice', userId: 'user-alice' }),
      mkRsvp({ id: 'rsvp-bob', userId: 'user-bob' }),
      mkRsvp({ id: 'rsvp-charlie', userId: 'user-charlie' }),
    ]
    mockExpenses = [
      mkExpense({
        id: 'exp-cabin',
        userId: 'user-test',
        amount: 480,
        description: 'Cabin',
        participantIds: [
          'ep-cabin-test',
          'ep-cabin-alice',
          'ep-cabin-bob',
          'ep-cabin-charlie',
        ],
      }),
      mkExpense({
        id: 'exp-groceries',
        userId: 'user-alice',
        amount: 92.4,
        description: 'Groceries',
        participantIds: [
          'ep-gro-test',
          'ep-gro-alice',
          'ep-gro-bob',
          'ep-gro-charlie',
        ],
      }),
      mkExpense({
        id: 'exp-firewood',
        userId: 'user-bob',
        amount: 35,
        description: 'Firewood',
        participantIds: [
          'ep-fw-test',
          'ep-fw-alice',
          'ep-fw-bob',
          'ep-fw-charlie',
        ],
      }),
      mkExpense({
        id: 'exp-tasting',
        userId: 'user-charlie',
        amount: 220,
        description: 'Tasting menu',
        // Test User factor 1, Charlie factor 1.5, Alice factor 1
        participantIds: ['ep-tm-test', 'ep-tm-charlie', 'ep-tm-alice'],
      }),
    ]
    mockParticipants = [
      // Cabin: equal among 4
      {
        ...BASE,
        id: 'ep-cabin-test',
        objectType: 'expenseParticipant',
        expenseId: 'exp-cabin',
        userId: 'user-test',
        factor: 1,
      },
      {
        ...BASE,
        id: 'ep-cabin-alice',
        objectType: 'expenseParticipant',
        expenseId: 'exp-cabin',
        userId: 'user-alice',
        factor: 1,
      },
      {
        ...BASE,
        id: 'ep-cabin-bob',
        objectType: 'expenseParticipant',
        expenseId: 'exp-cabin',
        userId: 'user-bob',
        factor: 1,
      },
      {
        ...BASE,
        id: 'ep-cabin-charlie',
        objectType: 'expenseParticipant',
        expenseId: 'exp-cabin',
        userId: 'user-charlie',
        factor: 1,
      },
      // Groceries
      {
        ...BASE,
        id: 'ep-gro-test',
        objectType: 'expenseParticipant',
        expenseId: 'exp-groceries',
        userId: 'user-test',
        factor: 1,
      },
      {
        ...BASE,
        id: 'ep-gro-alice',
        objectType: 'expenseParticipant',
        expenseId: 'exp-groceries',
        userId: 'user-alice',
        factor: 1,
      },
      {
        ...BASE,
        id: 'ep-gro-bob',
        objectType: 'expenseParticipant',
        expenseId: 'exp-groceries',
        userId: 'user-bob',
        factor: 1,
      },
      {
        ...BASE,
        id: 'ep-gro-charlie',
        objectType: 'expenseParticipant',
        expenseId: 'exp-groceries',
        userId: 'user-charlie',
        factor: 1,
      },
      // Firewood
      {
        ...BASE,
        id: 'ep-fw-test',
        objectType: 'expenseParticipant',
        expenseId: 'exp-firewood',
        userId: 'user-test',
        factor: 1,
      },
      {
        ...BASE,
        id: 'ep-fw-alice',
        objectType: 'expenseParticipant',
        expenseId: 'exp-firewood',
        userId: 'user-alice',
        factor: 1,
      },
      {
        ...BASE,
        id: 'ep-fw-bob',
        objectType: 'expenseParticipant',
        expenseId: 'exp-firewood',
        userId: 'user-bob',
        factor: 1,
      },
      {
        ...BASE,
        id: 'ep-fw-charlie',
        objectType: 'expenseParticipant',
        expenseId: 'exp-firewood',
        userId: 'user-charlie',
        factor: 1,
      },
      // Tasting menu (no Bob)
      {
        ...BASE,
        id: 'ep-tm-test',
        objectType: 'expenseParticipant',
        expenseId: 'exp-tasting',
        userId: 'user-test',
        factor: 1,
      },
      {
        ...BASE,
        id: 'ep-tm-charlie',
        objectType: 'expenseParticipant',
        expenseId: 'exp-tasting',
        userId: 'user-charlie',
        factor: 1.5,
      },
      {
        ...BASE,
        id: 'ep-tm-alice',
        objectType: 'expenseParticipant',
        expenseId: 'exp-tasting',
        userId: 'user-alice',
        factor: 1,
      },
    ]
    mockSettlements = [mkSettlement({ id: 'settle-1' })]
    mockTransfers = [
      // Active transfers that, when applied, leave Charlie with a +0.006
      // residual (rounded down from his true 26.136 - 26.13 = 0.006).
      mkTransfer({
        id: 'tr-paid',
        settlementId: 'settle-1',
        fromUserId: 'user-charlie',
        toUserId: 'user-alice',
        amount: 23.1,
        paidAt: '2026-04-27T05:55:17.000Z',
      }),
      mkTransfer({
        id: 'tr-1',
        settlementId: 'settle-1',
        fromUserId: 'user-alice',
        toUserId: 'user-test',
        amount: 145.41,
      }),
      mkTransfer({
        id: 'tr-2',
        settlementId: 'settle-1',
        fromUserId: 'user-bob',
        toUserId: 'user-test',
        amount: 116.85,
      }),
      mkTransfer({
        id: 'tr-3',
        settlementId: 'settle-1',
        fromUserId: 'user-charlie',
        toUserId: 'user-test',
        amount: 3.03,
      }),
    ]

    const wrapper = mountSection()

    expect(
      wrapper.find('[data-testid="settlement-drift-banner"]').exists()
    ).toBe(false)
    expect(
      wrapper.find('[data-testid="start-settlement-button"]').exists()
    ).toBe(false)
  })
})
