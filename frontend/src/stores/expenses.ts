import { defineStore } from 'pinia'
import { useMutation } from '@/composables/useMutation'
import { useAuthStore } from './auth'
import type { PoolApiResponse, PoolExpense } from '@/types/pool'

export const useExpensesStore = defineStore('expenses', () => {
  const { loading, error, create, update, destroy } = useMutation()

  async function createExpense(
    eventId: string,
    description: string,
    amount: number,
    startDate: string,
    endDate: string
  ) {
    const expenseId = crypto.randomUUID()
    const now = new Date().toISOString()
    const tempExpense: PoolExpense = {
      id: expenseId,
      objectType: 'expense',
      eventId,
      userId: useAuthStore().currentUserId ?? null,
      settlementId: null,
      description,
      amount,
      startDate,
      endDate,
      createdAt: now,
      updatedAt: now,
    }

    const result = await create(
      'Failed to create expense',
      tempExpense,
      (commandQueue) =>
        commandQueue.enqueue<PoolApiResponse>('POST', '/expenses', {
          event_id: eventId,
          description,
          amount,
          start_date: startDate,
          end_date: endDate,
          id: expenseId,
        })
    )
    return { expenseId, queued: result.queued }
  }

  async function updateExpense(
    id: string,
    changes: {
      description?: string
      amount?: number
      startDate?: string
      endDate?: string
    }
  ) {
    const apiChanges: Record<string, unknown> = {}
    if (changes.description !== undefined)
      apiChanges.description = changes.description
    if (changes.amount !== undefined) apiChanges.amount = changes.amount
    if (changes.startDate !== undefined)
      apiChanges.start_date = changes.startDate
    if (changes.endDate !== undefined) apiChanges.end_date = changes.endDate

    await update(
      'Failed to update expense',
      'expense',
      id,
      changes,
      (commandQueue) =>
        commandQueue.enqueue<PoolApiResponse>(
          'PUT',
          `/expenses/${id}`,
          apiChanges
        )
    )
  }

  async function deleteExpense(id: string) {
    await destroy('Failed to delete expense', 'expense', id, (commandQueue) =>
      commandQueue.enqueue('DELETE', `/expenses/${id}`)
    )
  }

  function $reset() {
    loading.value = false
    error.value = null
  }

  return {
    loading,
    error,
    createExpense,
    updateExpense,
    deleteExpense,
    $reset,
  }
})
