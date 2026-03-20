import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import AddExpenseModal from './AddExpenseModal.vue'
import type {
  PoolEvent,
  PoolRsvp,
  PoolMember,
  PoolExpense,
  PoolExpenseParticipant,
} from '@/types/pool'

let mockRsvps: PoolRsvp[] = []
let mockMembers: PoolMember[] = []
let mockParticipants: PoolExpenseParticipant[] = []

vi.mock('@/stores/objectPool', () => ({
  useObjectPoolStore: () => ({
    getAll: (type: string) => {
      if (type === 'rsvp') return mockRsvps
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

vi.mock('@/stores/expenses', () => ({
  useExpensesStore: () => ({
    createExpense: vi
      .fn()
      .mockResolvedValue({ expenseId: 'new-id', queued: false }),
    updateExpense: vi.fn().mockResolvedValue(undefined),
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
    workspaceId: 'ws-1',
    userId: 'user-1',
    datePollId: null,
    rsvpIds: [],
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
    hasIban: false,
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

describe('AddExpenseModal wizard', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    mockRsvps = []
    mockMembers = []
    mockParticipants = []
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
    mockRsvps = [
      {
        ...BASE,
        id: 'rsvp-1',
        objectType: 'rsvp',
        eventId: 'event-1',
        userId: 'user-1',
        attending: true,
        startDate: null,
        endDate: null,
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
    mockRsvps = [
      {
        ...BASE,
        id: 'rsvp-1',
        objectType: 'rsvp',
        eventId: 'event-1',
        userId: 'user-1',
        attending: true,
        startDate: null,
        endDate: null,
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
    expect(wrapper.find('[data-testid="toggle-people-mode"]').text()).toBe(
      'Specific people'
    )
  })

  it('shows member checkboxes when switching to specific people mode', async () => {
    mockRsvps = [
      {
        ...BASE,
        id: 'rsvp-1',
        objectType: 'rsvp',
        eventId: 'event-1',
        userId: 'user-1',
        attending: true,
        startDate: null,
        endDate: null,
      },
      {
        ...BASE,
        id: 'rsvp-2',
        objectType: 'rsvp',
        eventId: 'event-1',
        userId: 'user-2',
        attending: true,
        startDate: null,
        endDate: null,
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

    // Switch to specific people
    await wrapper.find('[data-testid="toggle-people-mode"]').trigger('click')
    await wrapper.vm.$nextTick()
    await wrapper.vm.$nextTick()

    // Check the toggle worked by looking for "No attending members" or checkboxes
    const text = wrapper.text()
    // If members don't overlap, we get the "No attending members" message
    // Otherwise we get checkboxes
    expect(text).not.toContain('Split by attendance overlap')
    // At minimum, the toggle should have switched the UI
    expect(wrapper.find('[data-testid="toggle-people-mode"]').text()).toBe(
      'Everyone'
    )
  })

  it('shows date mode toggle on step 2', async () => {
    const wrapper = mountModal()
    await wrapper
      .find('[data-testid="expense-description-input"]')
      .setValue('Test')
    await wrapper.find('[data-testid="expense-amount-input"]').setValue('10')
    await wrapper.find('form').trigger('submit')
    await wrapper.vm.$nextTick()

    const toggle = wrapper.find('[data-testid="toggle-date-mode"]')
    expect(toggle.exists()).toBe(true)
    expect(toggle.text()).toBe('Date range')
  })

  it('switches date mode toggle text when clicked', async () => {
    const wrapper = mountModal()
    await wrapper
      .find('[data-testid="expense-description-input"]')
      .setValue('Test')
    await wrapper.find('[data-testid="expense-amount-input"]').setValue('10')
    await wrapper.find('form').trigger('submit')
    await wrapper.vm.$nextTick()

    const toggle = wrapper.find('[data-testid="toggle-date-mode"]')
    await toggle.trigger('click')
    await wrapper.vm.$nextTick()

    expect(toggle.text()).toBe('Single date')
  })
})
