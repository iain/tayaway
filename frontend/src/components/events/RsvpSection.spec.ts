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
let mockExpenses: Array<{ eventId: string; userId: string }> = []

vi.mock('@/stores/objectPool', () => ({
  useObjectPoolStore: () => ({
    getAll: (type: string) => (type === 'expense' ? mockExpenses : []),
    findBy: (_type: string, field: string, value: unknown) =>
      mockMembers.find(
        (m) => (m as unknown as Record<string, unknown>)[field] === value
      ),
  }),
}))

const submitRsvpSpy = vi.fn()
vi.mock('@/stores/rsvps', () => ({
  useRsvpsStore: () => ({
    submitRsvp: submitRsvpSpy,
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
    attendance: null,
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
    timezone: 'Europe/Amsterdam',
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

function mountSection(
  rsvps: HydratedRsvp[],
  workspace?: HydratedEvent['workspace']
) {
  const event = mkEvent(rsvps)
  if (workspace !== undefined) event.workspace = workspace
  return mount(RsvpSection, {
    attachTo: document.body,
    props: { event, currentUserId: 'user-alice' },
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
    submitRsvpSpy.mockReset()
    mockExpenses = []
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

describe('RsvpSection on-behalf actions', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    submitRsvpSpy.mockReset()
    mockExpenses = []
    mockMembers = [
      mkMember({ id: 'member-alice', userId: 'user-alice', name: 'Alice' }),
      mkMember({ id: 'member-bob', userId: 'user-bob', name: 'Bob' }),
    ]
  })

  async function openMenuAndClick(
    wrapper: ReturnType<typeof mountSection>,
    label: string
  ) {
    await wrapper.find('[data-testid="rsvp-other-menu"]').trigger('click')
    await wrapper.vm.$nextTick()
    const item = wrapper
      .findAll('[role="menuitem"]')
      .find((b) => b.text() === label)
    expect(item, `menu item "${label}" should exist`).toBeDefined()
    await item!.trigger('click')
  }

  it('files an RSVP for another member from the no-response list', async () => {
    const workspace = {
      ...BASE,
      id: 'ws-1',
      objectType: 'workspace' as const,
      name: 'Test',
      timezone: 'Europe/Amsterdam',
      ownerUserId: 'user-alice',
      memberIds: ['member-bob'],
      members: [
        {
          ...BASE,
          id: 'member-bob',
          objectType: 'member' as const,
          userId: 'user-bob',
          email: 'bob@example.com',
          name: 'Bob',
          role: 'member' as const,
        },
      ],
    }

    const wrapper = mountSection([], workspace)
    await openMenuAndClick(wrapper, 'Mark as attending')

    expect(submitRsvpSpy).toHaveBeenCalledWith('event-1', true, {
      onBehalfOfUserId: 'user-bob',
    })
  })

  it("flips another member's RSVP from attending to declined", async () => {
    const rsvp = mkRsvp({
      id: 'rsvp-bob',
      userId: 'user-bob',
      createdByUserId: 'user-bob',
      member: mkMember({ id: 'member-bob', userId: 'user-bob', name: 'Bob' }),
    })

    const wrapper = mountSection([rsvp])
    await openMenuAndClick(wrapper, 'Mark as not attending')

    expect(submitRsvpSpy).toHaveBeenCalledWith('event-1', false, {
      onBehalfOfUserId: 'user-bob',
    })
  })

  it('blocks declining another member who has expenses and names them in the dialog', async () => {
    const rsvp = mkRsvp({
      id: 'rsvp-bob',
      userId: 'user-bob',
      createdByUserId: 'user-bob',
      member: mkMember({ id: 'member-bob', userId: 'user-bob', name: 'Bob' }),
    })
    mockExpenses = [{ eventId: 'event-1', userId: 'user-bob' }]

    const wrapper = mountSection([rsvp])
    await openMenuAndClick(wrapper, 'Mark as not attending')

    expect(submitRsvpSpy).not.toHaveBeenCalled()
    expect(wrapper.text()).toContain('Bob has expenses on this event')
  })
})
