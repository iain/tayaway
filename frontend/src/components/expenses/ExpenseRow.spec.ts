import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import ExpenseRow from './ExpenseRow.vue'
import type { PoolEvent, PoolExpense, PoolMember } from '@/types/pool'

let mockMembers: PoolMember[] = []

vi.mock('@/stores/objectPool', () => ({
  useObjectPoolStore: () => ({
    getAll: () => [],
    get: () => undefined,
    findBy: (_type: string, field: string, value: unknown) =>
      mockMembers.find(
        (m) => (m as unknown as Record<string, unknown>)[field] === value
      ),
    remove: vi.fn(),
  }),
}))

const deleteExpenseSpy = vi.fn().mockResolvedValue(undefined)
const revertExpenseSpy = vi.fn().mockResolvedValue(undefined)

vi.mock('@/stores/expenses', () => ({
  useExpensesStore: () => ({
    deleteExpense: deleteExpenseSpy,
    revertExpense: revertExpenseSpy,
  }),
}))

const BASE = {
  updatedAt: '2026-01-01T00:00:00.000Z',
  createdAt: '2026-01-01T00:00:00.000Z',
}

function mkEvent(): PoolEvent {
  return {
    ...BASE,
    id: 'event-1',
    objectType: 'event',
    name: 'Test',
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
  }
}

function mkExpense(overrides: Partial<PoolExpense> = {}): PoolExpense {
  return {
    ...BASE,
    id: 'exp-1',
    objectType: 'expense',
    eventId: 'event-1',
    userId: 'user-1',
    createdByUserId: 'user-1',
    settlementId: null,
    revertsExpenseId: null,
    description: 'Hotel',
    amount: 100,
    startDate: '2026-07-01',
    endDate: '2026-07-03',
    participantIds: [],
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

function mountRow(expense: PoolExpense) {
  return mount(ExpenseRow, {
    props: {
      expense,
      event: mkEvent(),
      currentUserId: 'user-1',
    },
    global: {
      stubs: {
        teleport: true,
        BaseModal: {
          template: '<div v-if="open"><slot /></div>',
          props: ['open', 'title', 'size'],
        },
      },
    },
  })
}

describe('ExpenseRow', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    deleteExpenseSpy.mockClear()
    revertExpenseSpy.mockClear()
    mockMembers = [mkMember()]
  })

  describe('Edit click routing', () => {
    it('emits "edit" when the action is allowed', async () => {
      const expense = mkExpense({
        permissions: { edit: { allowed: true } },
      })
      const wrapper = mountRow(expense)

      await wrapper.get('[data-testid="edit-expense"]').trigger('click')

      expect(wrapper.emitted('edit')).toBeTruthy()
      expect(
        wrapper.find('[data-testid="expense-blocked-modal"]').exists()
      ).toBe(false)
    })

    it('opens the explanation modal instead of emitting "edit" when behavior is modal', async () => {
      const expense = mkExpense({
        permissions: { edit: { allowed: false, reason: 'settled' } },
      })
      const wrapper = mountRow(expense)

      await wrapper.get('[data-testid="edit-expense"]').trigger('click')

      expect(wrapper.emitted('edit')).toBeFalsy()
      const modal = wrapper.find('[data-testid="expense-blocked-modal"]')
      expect(modal.exists()).toBe(true)
      expect(modal.text()).toContain('Revert')
    })
  })

  describe('Delete click routing', () => {
    it('calls deleteExpense when the action is allowed', async () => {
      const expense = mkExpense({
        permissions: { delete: { allowed: true } },
      })
      const wrapper = mountRow(expense)

      await wrapper.get('[data-testid="delete-expense"]').trigger('click')

      expect(deleteExpenseSpy).toHaveBeenCalledWith('exp-1')
    })

    it('opens the explanation modal instead of deleting when behavior is modal', async () => {
      const expense = mkExpense({
        permissions: { delete: { allowed: false, reason: 'settled' } },
      })
      const wrapper = mountRow(expense)

      await wrapper.get('[data-testid="delete-expense"]').trigger('click')

      expect(deleteExpenseSpy).not.toHaveBeenCalled()
      const modal = wrapper.find('[data-testid="expense-blocked-modal"]')
      expect(modal.exists()).toBe(true)
      expect(modal.text()).toContain('Revert')
    })
  })

  describe('filed-by badge', () => {
    it("shows the actor when an expense was filed on someone else's behalf", () => {
      mockMembers = [
        mkMember({ id: 'member-1', userId: 'user-1', name: 'Alice' }),
        mkMember({ id: 'member-2', userId: 'user-2', name: 'Bob' }),
      ]
      const expense = mkExpense({
        userId: 'user-1',
        createdByUserId: 'user-2',
      })
      const wrapper = mountRow(expense)

      const badge = wrapper.find('[data-testid="filed-by"]')
      expect(badge.exists()).toBe(true)
      expect(badge.text()).toContain('Bob')
    })

    it('hides the badge when the actor matches the subject', () => {
      const expense = mkExpense({
        userId: 'user-1',
        createdByUserId: 'user-1',
      })
      const wrapper = mountRow(expense)

      expect(wrapper.find('[data-testid="filed-by"]').exists()).toBe(false)
    })
  })
})
