import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import RsvpSection from './RsvpSection.vue'
import type {
  HydratedEvent,
  HydratedRsvp,
} from '@/composables/useHydratedEvent'
import type { PoolMember } from '@/types/pool'

let mockMembers: PoolMember[] = []

vi.mock('@/stores/objectPool', () => ({
  useObjectPoolStore: () => ({
    getAll: () => [],
    findBy: (_type: string, field: string, value: unknown) =>
      mockMembers.find(
        (m) => (m as unknown as Record<string, unknown>)[field] === value
      ),
  }),
}))

vi.mock('@/stores/rsvps', () => ({
  useRsvpsStore: () => ({
    submitRsvp: vi.fn(),
  }),
}))

const BASE = {
  updatedAt: '2026-01-01T00:00:00.000Z',
  createdAt: '2026-01-01T00:00:00.000Z',
}

function mkMember(overrides: Partial<PoolMember> = {}): PoolMember {
  return {
    ...BASE,
    id: 'member-bob',
    objectType: 'member',
    workspaceId: 'ws-1',
    userId: 'user-bob',
    email: 'bob@example.com',
    name: 'Bob',
    phoneNumber: null,
    birthday: null,
    locationName: null,
    latitude: null,
    longitude: null,
    role: 'member',
    ...overrides,
  }
}

function mkRsvp(overrides: Partial<HydratedRsvp>): HydratedRsvp {
  return {
    ...BASE,
    id: 'rsvp-1',
    objectType: 'rsvp',
    eventId: 'event-1',
    userId: 'user-alice',
    createdByUserId: 'user-alice',
    attending: true,
    startDate: null,
    endDate: null,
    member: mkMember({
      id: 'member-alice',
      userId: 'user-alice',
      name: 'Alice',
    }),
    ...overrides,
  }
}

function mkEvent(rsvps: HydratedRsvp[]): HydratedEvent {
  return {
    ...BASE,
    id: 'event-1',
    objectType: 'event',
    name: 'Trip',
    description: null,
    startDate: '2026-07-01',
    endDate: '2026-07-07',
    locationName: null,
    latitude: null,
    longitude: null,
    workspaceId: 'ws-1',
    userId: 'user-alice',
    datePollId: null,
    rsvpIds: rsvps.map((r) => r.id),
    workspace: undefined,
    member: undefined,
    datePoll: null,
    rsvps,
  }
}

function mountSection(rsvps: HydratedRsvp[]) {
  return mount(RsvpSection, {
    props: { event: mkEvent(rsvps), currentUserId: 'user-alice' },
    global: {
      stubs: {
        teleport: true,
        BaseModal: {
          template: '<div v-if="open"><slot /></div>',
          props: ['open'],
        },
        BaseCard: { template: '<div><slot /></div>' },
        SectionHeading: { template: '<div><slot /></div>' },
        DateRangeDisplay: { template: '<span></span>' },
        AppButton: { template: '<button><slot /></button>' },
        TextButton: { template: '<button><slot /></button>' },
        IconButton: { template: '<button><slot /></button>' },
        CalendarMonth: { template: '<div></div>' },
      },
    },
  })
}

describe('RsvpSection filed-by badge', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    mockMembers = [
      mkMember({ id: 'member-alice', userId: 'user-alice', name: 'Alice' }),
      mkMember({ id: 'member-bob', userId: 'user-bob', name: 'Bob' }),
    ]
  })

  it("shows the actor's name when an RSVP was filed on someone else's behalf", () => {
    const rsvp = mkRsvp({
      userId: 'user-alice',
      createdByUserId: 'user-bob',
    })

    const wrapper = mountSection([rsvp])

    const badge = wrapper.find('[data-testid="rsvp-filed-by"]')
    expect(badge.exists()).toBe(true)
    expect(badge.text()).toContain('Bob')
  })

  it('hides the badge when the actor matches the subject', () => {
    const rsvp = mkRsvp({
      userId: 'user-alice',
      createdByUserId: 'user-alice',
    })

    const wrapper = mountSection([rsvp])

    expect(wrapper.find('[data-testid="rsvp-filed-by"]').exists()).toBe(false)
  })
})
