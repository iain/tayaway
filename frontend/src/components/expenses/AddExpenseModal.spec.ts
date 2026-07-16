import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import AddExpenseModal from './AddExpenseModal.vue'
import type {
  PoolEvent,
  PoolAttendance,
  PoolMember,
  PoolExpense,
  PoolExpenseParticipant,
} from '@/types/pool'

let mockAttendances: PoolAttendance[] = []
let mockMembers: PoolMember[] = []
let mockParticipants: PoolExpenseParticipant[] = []

vi.mock('@/stores/objectPool', () => ({
  useObjectPoolStore: () => ({
    getAll: (type: string) => {
      if (type === 'attendance') return mockAttendances
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
    importObjects: vi.fn(),
  }),
}))

const createExpenseSpy = vi
  .fn()
  .mockResolvedValue({ expenseId: 'new-id', queued: false })
const updateExpenseSpy = vi.fn().mockResolvedValue(undefined)

vi.mock('@/stores/expenses', () => ({
  useExpensesStore: () => ({
    createExpense: createExpenseSpy,
    updateExpense: updateExpenseSpy,
    loading: { value: false },
    error: { value: null },
  }),
}))

vi.mock('@/stores/auth', () => ({
  useAuthStore: () => ({
    currentUserId: 'user-1',
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
    name: 'Test Event',
    description: null,
    startDate: '2026-07-01',
    endDate: '2026-07-07',
    locationName: null,
    latitude: null,
    longitude: null,
    timezone: 'Europe/Amsterdam',
    workspaceId: 'ws-1',
    userId: 'user-1',
    datePollId: null,
    attendanceIds: [],
    ...overrides,
  }
}

function mkMember(overrides: Partial<PoolMember> = {}): PoolMember {
  return {
    ...BASE,
    id: 'member-1',
    objectType: 'member',
    workspaceId: 'ws-1',
    userId: 'user-1',
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

function mountModal(event: PoolEvent = mkEvent(), expense?: PoolExpense) {
  return mount(AddExpenseModal, {
    props: { open: true, event, expense },
    global: {
      stubs: {
        teleport: true,
        BaseModal: {
          template: '<div><slot /></div>',
          props: ['open', 'title', 'size', 'preventClose'],
        },
      },
    },
  })
}

// Triggers the `watch(() => props.open)` hook that initializes dates/participants.
// The watcher isn't `immediate`, so mounting with `open: true` alone doesn't fire it.
async function mountModalOpened(
  event: PoolEvent = mkEvent(),
  expense?: PoolExpense
) {
  const wrapper = mount(AddExpenseModal, {
    props: { open: false, event, expense },
    global: {
      stubs: {
        teleport: true,
        BaseModal: {
          template: '<div><slot /></div>',
          props: ['open', 'title', 'size', 'preventClose'],
        },
      },
    },
  })
  await wrapper.setProps({ open: true })
  await wrapper.vm.$nextTick()
  return wrapper
}

describe('AddExpenseModal wizard', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    mockAttendances = []
    mockMembers = []
    mockParticipants = []
    createExpenseSpy.mockClear()
    updateExpenseSpy.mockClear()
  })

  it('renders step indicator with 3 dots', () => {
    const wrapper = mountModal()
    const dots = wrapper.find('[data-testid="wizard-steps"]')
    expect(dots.exists()).toBe(true)
    expect(dots.findAll('div').length).toBe(3)
  })

  it('starts on step 1 with details inputs', () => {
    const wrapper = mountModal()
    expect(
      wrapper.find('[data-testid="expense-description-input"]').exists()
    ).toBe(true)
    expect(wrapper.find('[data-testid="expense-amount-input"]').exists()).toBe(
      true
    )
  })

  it('disables Next when description and amount are empty', () => {
    const wrapper = mountModal()
    const submitBtn = wrapper.find('button[type="submit"]')
    expect(submitBtn.attributes('disabled')).toBeDefined()
  })

  it('navigates to step 2 when Next is clicked with valid inputs', async () => {
    const wrapper = mountModal()
    const descInput = wrapper.find('[data-testid="expense-description-input"]')
    const amountInput = wrapper.find('[data-testid="expense-amount-input"]')

    await descInput.setValue('Dinner')
    await amountInput.setValue('42.50')

    await wrapper.find('form').trigger('submit')
    await wrapper.vm.$nextTick()

    // Should now be on step 2 — date toggle should be visible
    expect(wrapper.find('[data-testid="toggle-date-mode"]').exists()).toBe(true)
  })

  it('navigates back to step 1 from step 2', async () => {
    const wrapper = mountModal()
    await wrapper
      .find('[data-testid="expense-description-input"]')
      .setValue('Test')
    await wrapper.find('[data-testid="expense-amount-input"]').setValue('10')
    await wrapper.find('form').trigger('submit')
    await wrapper.vm.$nextTick()

    // Click "Back" button (cancel button when step > 1)
    const buttons = wrapper.findAll('button')
    const backBtn = buttons.find((b) => b.text() === 'Back')
    expect(backBtn).toBeDefined()
    await backBtn!.trigger('click')
    await wrapper.vm.$nextTick()

    // Should be back on step 1
    expect(
      wrapper.find('[data-testid="expense-description-input"]').exists()
    ).toBe(true)
  })

  it('preserves form state when navigating back', async () => {
    const wrapper = mountModal()
    await wrapper
      .find('[data-testid="expense-description-input"]')
      .setValue('Dinner')
    await wrapper.find('[data-testid="expense-amount-input"]').setValue('99')
    await wrapper.find('form').trigger('submit')
    await wrapper.vm.$nextTick()

    // Go back
    const buttons = wrapper.findAll('button')
    const backBtn = buttons.find((b) => b.text() === 'Back')
    await backBtn!.trigger('click')
    await wrapper.vm.$nextTick()

    const descInput = wrapper.find<HTMLInputElement>(
      '[data-testid="expense-description-input"]'
    )
    expect(descInput.element.value).toBe('Dinner')
  })

  it('navigates to step 3 and shows people toggle', async () => {
    mockAttendances = [
      {
        ...BASE,
        id: 'att-1',
        objectType: 'attendance',
        eventId: 'event-1',
        userId: 'user-1',
        guestId: null,
        hostUserId: null,
        status: 'going',
        days: null,
        createdByUserId: null,
      },
    ]
    mockMembers = [mkMember()]

    const wrapper = mountModal()
    // Step 1 → 2
    await wrapper
      .find('[data-testid="expense-description-input"]')
      .setValue('Test')
    await wrapper.find('[data-testid="expense-amount-input"]').setValue('10')
    await wrapper.find('form').trigger('submit')
    await wrapper.vm.$nextTick()

    // Step 2 → 3
    await wrapper.find('form').trigger('submit')
    await wrapper.vm.$nextTick()

    expect(wrapper.find('[data-testid="toggle-people-mode"]').exists()).toBe(
      true
    )
  })

  it('defaults to "Everyone" mode on step 3', async () => {
    mockAttendances = [
      {
        ...BASE,
        id: 'att-1',
        objectType: 'attendance',
        eventId: 'event-1',
        userId: 'user-1',
        guestId: null,
        hostUserId: null,
        status: 'going',
        days: null,
        createdByUserId: null,
      },
    ]
    mockMembers = [mkMember()]

    const wrapper = mountModal()
    await wrapper
      .find('[data-testid="expense-description-input"]')
      .setValue('Test')
    await wrapper.find('[data-testid="expense-amount-input"]').setValue('10')
    await wrapper.find('form').trigger('submit')
    await wrapper.vm.$nextTick()
    await wrapper.find('form').trigger('submit')
    await wrapper.vm.$nextTick()

    expect(wrapper.text()).toContain('Split by attendance overlap')
    const toggle = wrapper.find('[data-testid="toggle-people-mode"]')
    expect(toggle.text()).toContain('Everyone')
    expect(toggle.text()).toContain('Specific people')
  })

  it('shows member checkboxes when switching to specific people mode', async () => {
    mockAttendances = [
      {
        ...BASE,
        id: 'att-1',
        objectType: 'attendance',
        eventId: 'event-1',
        userId: 'user-1',
        guestId: null,
        hostUserId: null,
        status: 'going',
        days: null,
        createdByUserId: null,
      },
      {
        ...BASE,
        id: 'att-2',
        objectType: 'attendance',
        eventId: 'event-1',
        userId: 'user-2',
        guestId: null,
        hostUserId: null,
        status: 'going',
        days: null,
        createdByUserId: null,
      },
    ]
    mockMembers = [
      mkMember({ id: 'member-1', userId: 'user-1', name: 'Alice' }),
      mkMember({ id: 'member-2', userId: 'user-2', name: 'Bob' }),
    ]

    const wrapper = mountModal()
    await wrapper
      .find('[data-testid="expense-description-input"]')
      .setValue('Test')
    await wrapper.find('[data-testid="expense-amount-input"]').setValue('10')
    await wrapper.find('form').trigger('submit')
    await wrapper.vm.$nextTick()
    await wrapper.find('form').trigger('submit')
    await wrapper.vm.$nextTick()

    // Switch to specific people by clicking the "Specific people" button
    const buttons = wrapper
      .find('[data-testid="toggle-people-mode"]')
      .findAll('button')
    const specificBtn = buttons.find((b) => b.text() === 'Specific people')
    await specificBtn!.trigger('click')
    await wrapper.vm.$nextTick()
    await wrapper.vm.$nextTick()

    // Check the toggle worked
    const text = wrapper.text()
    expect(text).not.toContain('Split by attendance overlap')
  })

  it('shows date mode segmented control on step 2', async () => {
    const wrapper = mountModal()
    await wrapper
      .find('[data-testid="expense-description-input"]')
      .setValue('Test')
    await wrapper.find('[data-testid="expense-amount-input"]').setValue('10')
    await wrapper.find('form').trigger('submit')
    await wrapper.vm.$nextTick()

    const toggle = wrapper.find('[data-testid="toggle-date-mode"]')
    expect(toggle.exists()).toBe(true)
    expect(toggle.text()).toContain('Single date')
    expect(toggle.text()).toContain('Date range')
  })

  it('switches date mode when clicking Date range button', async () => {
    const wrapper = mountModal()
    await wrapper
      .find('[data-testid="expense-description-input"]')
      .setValue('Test')
    await wrapper.find('[data-testid="expense-amount-input"]').setValue('10')
    await wrapper.find('form').trigger('submit')
    await wrapper.vm.$nextTick()

    const buttons = wrapper
      .find('[data-testid="toggle-date-mode"]')
      .findAll('button')
    const rangeBtn = buttons.find((b) => b.text() === 'Date range')
    await rangeBtn!.trigger('click')
    await wrapper.vm.$nextTick()

    // Date range button should now have the active style
    expect(rangeBtn!.classes()).toContain('bg-amber-100')
  })

  it('submits participants with factors set via the stepper', async () => {
    mockAttendances = [
      {
        ...BASE,
        id: 'att-1',
        objectType: 'attendance',
        eventId: 'event-1',
        userId: 'alice',
        guestId: null,
        hostUserId: null,
        status: 'going',
        days: null,
        createdByUserId: null,
      },
      {
        ...BASE,
        id: 'att-2',
        objectType: 'attendance',
        eventId: 'event-1',
        userId: 'bob',
        guestId: null,
        hostUserId: null,
        status: 'going',
        days: null,
        createdByUserId: null,
      },
    ]
    mockMembers = [
      mkMember({ id: 'm-alice', userId: 'alice', name: 'Alice' }),
      mkMember({ id: 'm-bob', userId: 'bob', name: 'Bob' }),
    ]

    const wrapper = await mountModalOpened()

    // Step 1 → 2
    await wrapper
      .find('[data-testid="expense-description-input"]')
      .setValue('Dinner')
    await wrapper.find('[data-testid="expense-amount-input"]').setValue('30')
    await wrapper.find('form').trigger('submit')
    await wrapper.vm.$nextTick()

    // Step 2 → 3
    await wrapper.find('form').trigger('submit')
    await wrapper.vm.$nextTick()

    // Switch to "Specific people" (second button in the toggle)
    const toggleButtons = wrapper.findAll(
      '[data-testid="toggle-people-mode"] button'
    )
    await toggleButtons[1]!.trigger('click')
    await wrapper.vm.$nextTick()

    // Select Alice, bump factor to 2 (two + clicks)
    await wrapper.find('[data-testid="participant-alice"] input').setValue(true)
    const alicePlus = wrapper.findAll('[data-testid="factor-alice"] button')[1]!
    await alicePlus.trigger('click')
    await alicePlus.trigger('click')

    // Select Bob, drop factor to ½ (one - click)
    await wrapper.find('[data-testid="participant-bob"] input').setValue(true)
    const bobMinus = wrapper.findAll('[data-testid="factor-bob"] button')[0]!
    await bobMinus.trigger('click')

    await wrapper.find('form').trigger('submit')
    await wrapper.vm.$nextTick()

    expect(createExpenseSpy).toHaveBeenCalledTimes(1)
    const call = createExpenseSpy.mock.calls[0]!
    // Signature: (eventId, description, amount, startDate, endDate, participants?)
    expect(call[5]).toEqual([
      { userId: 'alice', factor: 2 },
      { userId: 'bob', factor: 0.5 },
    ])
  })

  it('disables the decrement button at ½ and the increment button at 9½', async () => {
    mockAttendances = [
      {
        ...BASE,
        id: 'att-1',
        objectType: 'attendance',
        eventId: 'event-1',
        userId: 'alice',
        guestId: null,
        hostUserId: null,
        status: 'going',
        days: null,
        createdByUserId: null,
      },
    ]
    mockMembers = [mkMember({ id: 'm-alice', userId: 'alice', name: 'Alice' })]

    const wrapper = await mountModalOpened()
    await wrapper
      .find('[data-testid="expense-description-input"]')
      .setValue('Dinner')
    await wrapper.find('[data-testid="expense-amount-input"]').setValue('10')
    await wrapper.find('form').trigger('submit')
    await wrapper.vm.$nextTick()
    await wrapper.find('form').trigger('submit')
    await wrapper.vm.$nextTick()

    const toggleButtons = wrapper.findAll(
      '[data-testid="toggle-people-mode"] button'
    )
    await toggleButtons[1]!.trigger('click')
    await wrapper.vm.$nextTick()

    await wrapper.find('[data-testid="participant-alice"] input').setValue(true)
    await wrapper.vm.$nextTick()

    const [minus, plus] = wrapper.findAll('[data-testid="factor-alice"] button')
    // Decrement once → ½, then button disabled
    await minus!.trigger('click')
    expect(wrapper.find('[data-testid="factor-value-alice"]').text()).toBe('½')
    expect((minus!.element as HTMLButtonElement).disabled).toBe(true)

    // Bring it back up and max it out
    await plus!.trigger('click') // ½ → 1
    for (let i = 0; i < 20; i++) {
      if ((plus!.element as HTMLButtonElement).disabled) break
      await plus!.trigger('click')
    }
    expect(wrapper.find('[data-testid="factor-value-alice"]').text()).toBe('9½')
  })
})
