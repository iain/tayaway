import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import RsvpSection from './RsvpSection.vue'
import type {
  HydratedAttendance,
  HydratedEvent,
} from '@/composables/useHydratedEvent'
import type { PoolGuest, PoolMember } from '@/types/pool'

let mockMembers: PoolMember[] = []
let mockGuests: PoolGuest[] = []
let mockExpenses: Array<{ eventId: string; userId: string }> = []

vi.mock('@/stores/objectPool', () => ({
  useObjectPoolStore: () => ({
    getAll: (type: string) =>
      type === 'expense' ? mockExpenses : type === 'guest' ? mockGuests : [],
    findBy: (_type: string, field: string, value: unknown) =>
      mockMembers.find(
        (m) => (m as unknown as Record<string, unknown>)[field] === value
      ),
  }),
}))

const submitMemberAttendanceSpy = vi.fn()
const removeGuestSpy = vi.fn()
const upsertGuestAttendanceSpy = vi.fn()
vi.mock('@/stores/attendances', () => ({
  useAttendancesStore: () => ({
    submitMemberAttendance: submitMemberAttendanceSpy,
    removeGuest: removeGuestSpy,
    upsertGuestAttendance: upsertGuestAttendanceSpy,
  }),
}))

const renameGuestSpy = vi.fn()
vi.mock('@/stores/guests', () => ({
  useGuestsStore: () => ({
    renameGuest: renameGuestSpy,
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

function mkAttendance(
  overrides: Partial<HydratedAttendance> = {}
): HydratedAttendance {
  const member = mkMember({
    id: 'member-alice',
    userId: 'user-alice',
    name: 'Alice',
  })
  return {
    ...BASE,
    id: 'att-1',
    objectType: 'attendance',
    eventId: 'event-1',
    userId: 'user-alice',
    guestId: null,
    hostUserId: null,
    status: 'going',
    days: null,
    createdByUserId: 'user-alice',
    attendee: {
      name: member.name!,
      isGuest: false,
      billingUserId: 'user-alice',
      member,
      guest: undefined,
      hostMember: undefined,
    },
    ...overrides,
  }
}

function mkGuestAttendance(
  overrides: Partial<HydratedAttendance> = {}
): HydratedAttendance {
  const hostMember = mkMember({
    id: 'member-alice',
    userId: 'user-alice',
    name: 'Alice',
  })
  return mkAttendance({
    id: 'att-guest',
    userId: null,
    guestId: 'guest-emma',
    hostUserId: 'user-alice',
    attendee: {
      name: 'Emma',
      isGuest: true,
      billingUserId: 'user-alice',
      member: undefined,
      guest: {
        ...BASE,
        id: 'guest-emma',
        objectType: 'guest',
        workspaceId: 'ws-1',
        name: 'Emma',
        placeholder: false,
        createdByUserId: 'user-alice',
      },
      hostMember,
    },
    ...overrides,
  })
}

function mkEvent(attendances: HydratedAttendance[]): HydratedEvent {
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
    attendanceIds: attendances.map((a) => a.id),
    workspace: undefined,
    member: undefined,
    datePoll: null,
    attendances,
  }
}

function mountSection(
  attendances: HydratedAttendance[],
  workspace?: HydratedEvent['workspace']
) {
  const event = mkEvent(attendances)
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

beforeEach(() => {
  setActivePinia(createPinia())
  submitMemberAttendanceSpy.mockReset()
  removeGuestSpy.mockReset()
  upsertGuestAttendanceSpy.mockReset()
  renameGuestSpy.mockReset()
  mockExpenses = []
  mockGuests = []
  mockMembers = [
    mkMember({ id: 'member-alice', userId: 'user-alice', name: 'Alice' }),
    mkMember({ id: 'member-bob', userId: 'user-bob', name: 'Bob' }),
  ]
})

describe('RsvpSection filed-by badge', () => {
  it("shows the actor's name when an RSVP was filed on someone else's behalf", () => {
    const attendance = mkAttendance({
      userId: 'user-alice',
      createdByUserId: 'user-bob',
    })

    const wrapper = mountSection([attendance])

    const badge = wrapper.find('[data-testid="rsvp-filed-by"]')
    expect(badge.exists()).toBe(true)
    expect(badge.text()).toContain('Bob')
  })

  it('hides the badge when the actor matches the subject', () => {
    const attendance = mkAttendance({
      userId: 'user-alice',
      createdByUserId: 'user-alice',
    })

    const wrapper = mountSection([attendance])

    expect(wrapper.find('[data-testid="rsvp-filed-by"]').exists()).toBe(false)
  })
})

describe('RsvpSection on-behalf actions', () => {
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

  it('files an attendance for another member from the no-response list', async () => {
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

    expect(submitMemberAttendanceSpy).toHaveBeenCalledWith('event-1', 'going', {
      onBehalfOfUserId: 'user-bob',
    })
  })

  it("flips another member's attendance from going to declined", async () => {
    const attendance = mkAttendance({
      id: 'att-bob',
      userId: 'user-bob',
      createdByUserId: 'user-bob',
      attendee: {
        name: 'Bob',
        isGuest: false,
        billingUserId: 'user-bob',
        member: mkMember(),
        guest: undefined,
        hostMember: undefined,
      },
    })

    const wrapper = mountSection([attendance])
    await openMenuAndClick(wrapper, 'Mark as not attending')

    expect(submitMemberAttendanceSpy).toHaveBeenCalledWith(
      'event-1',
      'declined',
      { onBehalfOfUserId: 'user-bob' }
    )
  })

  it('blocks declining another member who has expenses and names them in the dialog', async () => {
    const attendance = mkAttendance({
      id: 'att-bob',
      userId: 'user-bob',
      createdByUserId: 'user-bob',
      attendee: {
        name: 'Bob',
        isGuest: false,
        billingUserId: 'user-bob',
        member: mkMember(),
        guest: undefined,
        hostMember: undefined,
      },
    })
    mockExpenses = [{ eventId: 'event-1', userId: 'user-bob' }]

    const wrapper = mountSection([attendance])
    await openMenuAndClick(wrapper, 'Mark as not attending')

    expect(submitMemberAttendanceSpy).not.toHaveBeenCalled()
    expect(wrapper.text()).toContain('Bob has expenses on this event')
  })
})

describe('RsvpSection guests', () => {
  it('lists a going guest with their host and days', () => {
    const wrapper = mountSection([
      mkAttendance(),
      mkGuestAttendance({ days: ['2026-07-02', '2026-07-03'] }),
    ])

    const row = wrapper.find('[data-testid="attendance-guest-row"]')
    expect(row.exists()).toBe(true)
    expect(row.text()).toContain('Emma')
    expect(row.text()).toContain('guest of Alice')
  })

  it('removes a guest via the row button — a decline, not a delete', async () => {
    const wrapper = mountSection([mkAttendance(), mkGuestAttendance()])

    await wrapper.find('[data-testid="guest-remove"]').trigger('click')

    expect(removeGuestSpy).toHaveBeenCalledWith('event-1', 'att-guest')
  })

  it('blocks declining yourself while your guests are going', async () => {
    const wrapper = mountSection([mkAttendance(), mkGuestAttendance()])

    await wrapper.find('[data-testid="rsvp-decline"]').trigger('click')

    expect(submitMemberAttendanceSpy).not.toHaveBeenCalled()
    expect(wrapper.text()).toContain('You have guests going on this event')
  })

  it('does not block declining when your guests are merely pending', async () => {
    const wrapper = mountSection([
      mkAttendance(),
      mkGuestAttendance({ status: 'pending' }),
    ])

    await wrapper.find('[data-testid="rsvp-decline"]').trigger('click')

    expect(submitMemberAttendanceSpy).toHaveBeenCalledWith(
      'event-1',
      'declined',
      { onBehalfOfUserId: undefined }
    )
  })

  it('creates a new named guest from the add-guest modal', async () => {
    const wrapper = mountSection([mkAttendance()])

    await wrapper.find('[data-testid="rsvp-add-guest"]').trigger('click')
    await wrapper.find('[data-testid="guest-name-input"]').setValue('Milo')
    await wrapper.find('[data-testid="guest-save"]').trigger('click')

    expect(upsertGuestAttendanceSpy).toHaveBeenCalledWith('event-1', 'ws-1', {
      name: 'Milo',
      days: null,
    })
  })

  it('lists a pending guest under No Response so their host can re-confirm', () => {
    const wrapper = mountSection([
      mkAttendance(),
      mkGuestAttendance({ status: 'pending' }),
    ])

    expect(wrapper.find('[data-testid="attendance-guest-row"]').exists()).toBe(
      false
    )
    expect(wrapper.text()).toContain('No Response (1)')
    const row = wrapper.find('[data-testid="pending-guest-row"]')
    expect(row.exists()).toBe(true)
    expect(row.text()).toContain('Emma')
    expect(row.text()).toContain('guest of Alice')
  })

  it("re-confirms a pending guest's days from the No Response row", async () => {
    const wrapper = mountSection([
      mkAttendance(),
      mkGuestAttendance({ status: 'pending' }),
    ])

    await wrapper.find('[data-testid="rsvp-other-menu"]').trigger('click')
    await wrapper.vm.$nextTick()
    const item = wrapper
      .findAll('[role="menuitem"]')
      .find((b) => b.text() === 'Choose days')
    expect(item, 'menu item "Choose days" should exist').toBeDefined()
    await item!.trigger('click')
    await wrapper.find('[data-testid="guest-save"]').trigger('click')

    // A pending row has no days, so the picker presets the whole event,
    // which saves as the canonical null.
    expect(upsertGuestAttendanceSpy).toHaveBeenCalledWith('event-1', 'ws-1', {
      guestId: 'guest-emma',
      days: null,
    })
  })

  it('offers existing non-placeholder guests in the picker', async () => {
    mockGuests = [
      {
        ...BASE,
        id: 'guest-nora',
        objectType: 'guest',
        workspaceId: 'ws-1',
        name: 'Nora',
        placeholder: false,
        createdByUserId: null,
      },
      {
        ...BASE,
        id: 'guest-ph',
        objectType: 'guest',
        workspaceId: 'ws-1',
        name: 'Guest 1 (Alice)',
        placeholder: true,
        createdByUserId: null,
      },
    ]
    const wrapper = mountSection([mkAttendance()])

    await wrapper.find('[data-testid="rsvp-add-guest"]').trigger('click')

    const picker = wrapper.find('[data-testid="guest-picker-existing"]')
    expect(picker.text()).toContain('Nora')
    expect(picker.text()).not.toContain('Guest 1 (Alice)')
  })
})

describe('RsvpSection pending rows', () => {
  it('lists a pending member under No Response', () => {
    const workspace = {
      ...BASE,
      id: 'ws-1',
      objectType: 'workspace' as const,
      name: 'Test',
      timezone: 'Europe/Amsterdam',
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
    const pending = mkAttendance({
      id: 'att-bob',
      userId: 'user-bob',
      status: 'pending',
      attendee: {
        name: 'Bob',
        isGuest: false,
        billingUserId: 'user-bob',
        member: mkMember(),
        guest: undefined,
        hostMember: undefined,
      },
    })

    const wrapper = mountSection([pending], workspace)

    expect(wrapper.text()).toContain('No Response (1)')
    expect(wrapper.text()).not.toContain('Attending (')
  })
})
