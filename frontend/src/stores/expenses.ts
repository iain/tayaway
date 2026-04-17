import { defineStore } from 'pinia'
import { useMutation } from '@/composables/useMutation'
import { useAuthStore } from './auth'
import { useObjectPoolStore } from './objectPool'
import type {
  PoolApiResponse,
  PoolExpense,
  PoolExpenseParticipant,
} from '@/types/pool'

export interface ExpenseParticipantInput {
  userId: string
  factor: number
}

export const useExpensesStore = defineStore('expenses', () => {
  const { loading, error, create, update, destroy } = useMutation()

  async function createExpense(
    eventId: string,
    description: string,
    amount: number,
    startDate: string,
    endDate: string,
    participants?: ExpenseParticipantInput[]
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

    const tempParticipants: PoolExpenseParticipant[] = (participants ?? []).map(
      (p) => {
        const id = crypto.randomUUID()
        tempExpense.participantIds.push(id)
        return {
          id,
          objectType: 'expenseParticipant' as const,
          expenseId,
          userId: p.userId,
          factor: p.factor,
          createdAt: now,
          updatedAt: now,
        }
      }
    )

    if (tempParticipants.length > 0) {
      pool.importObjects(tempParticipants)
    }

    const apiBody: Record<string, unknown> = {
      event_id: eventId,
      description,
      amount,
      start_date: startDate,
      end_date: endDate,
      id: expenseId,
    }
    if (participants && participants.length > 0) {
      apiBody.participants = participants.map((p) => ({
        user_id: p.userId,
        factor: p.factor,
      }))
    }

    const result = await create(
      'Failed to create expense',
      tempExpense,
      (commandQueue) =>
        commandQueue.enqueue<PoolApiResponse>('POST', '/expenses', apiBody)
    )

    if (!result.queued) {
      for (const tp of tempParticipants) {
        pool.remove('expenseParticipant', tp.id)
      }
    }

    return { expenseId, queued: result.queued }
  }

  async function updateExpense(
    id: string,
    changes: {
      description?: string
      amount?: number
      startDate?: string
      endDate?: string
      participants?: ExpenseParticipantInput[]
    }
  ) {
    const apiChanges: Record<string, unknown> = {}
    if (changes.description !== undefined)
      apiChanges.description = changes.description
    if (changes.amount !== undefined) apiChanges.amount = changes.amount
    if (changes.startDate !== undefined)
      apiChanges.start_date = changes.startDate
    if (changes.endDate !== undefined) apiChanges.end_date = changes.endDate
    if (changes.participants !== undefined)
      apiChanges.participants = changes.participants.map((p) => ({
        user_id: p.userId,
        factor: p.factor,
      }))

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
