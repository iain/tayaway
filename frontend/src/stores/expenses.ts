import { defineStore } from 'pinia'
import { useMutation } from '@/composables/useMutation'
import { useAuthStore } from './auth'
import { useObjectPoolStore } from './objectPool'
import type {
  PoolApiResponse,
  PoolExpense,
  PoolExpenseParticipant,
} from '@/types/pool'

export const useExpensesStore = defineStore('expenses', () => {
  const { loading, error, create, update, destroy } = useMutation()

  async function createExpense(
    eventId: string,
    description: string,
    amount: number,
    startDate: string,
    endDate: string,
    participantIds?: string[]
  ) {
    const expenseId = crypto.randomUUID()
    const now = new Date().toISOString()
    const pool = useObjectPoolStore()

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
      participantIds: [],
      createdAt: now,
      updatedAt: now,
    }

    // Create temp participant objects for optimistic UI
    const tempParticipants: PoolExpenseParticipant[] = (
      participantIds ?? []
    ).map((userId) => {
      const id = crypto.randomUUID()
      tempExpense.participantIds.push(id)
      return {
        id,
        objectType: 'expenseParticipant' as const,
        expenseId,
        userId,
        createdAt: now,
        updatedAt: now,
      }
    })

    // Insert temp participants into pool before the create call
    for (const tp of tempParticipants) {
      pool.importObjects([tp])
    }

    const apiBody: Record<string, unknown> = {
      event_id: eventId,
      description,
      amount,
      start_date: startDate,
      end_date: endDate,
      id: expenseId,
    }
    if (participantIds && participantIds.length > 0) {
      apiBody.participant_ids = participantIds
    }

    const result = await create(
      'Failed to create expense',
      tempExpense,
      (commandQueue) =>
        commandQueue.enqueue<PoolApiResponse>('POST', '/expenses', apiBody)
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
      participantIds?: string[]
    }
  ) {
    const apiChanges: Record<string, unknown> = {}
    if (changes.description !== undefined)
      apiChanges.description = changes.description
    if (changes.amount !== undefined) apiChanges.amount = changes.amount
    if (changes.startDate !== undefined)
      apiChanges.start_date = changes.startDate
    if (changes.endDate !== undefined) apiChanges.end_date = changes.endDate
    if (changes.participantIds !== undefined)
      apiChanges.participant_ids = changes.participantIds

    // For optimistic update, don't pass participantIds to pool patch (handled via server response)
    const poolChanges: Partial<PoolExpense> = {}
    if (changes.description !== undefined)
      poolChanges.description = changes.description
    if (changes.amount !== undefined) poolChanges.amount = changes.amount
    if (changes.startDate !== undefined)
      poolChanges.startDate = changes.startDate
    if (changes.endDate !== undefined) poolChanges.endDate = changes.endDate

    await update(
      'Failed to update expense',
      'expense',
      id,
      poolChanges,
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
