import { defineStore } from 'pinia'
import { useMutation } from '@/composables/useMutation'
import type { PoolApiResponse } from '@/types/pool'

export const useSettlementsStore = defineStore('settlements', () => {
  const { loading, error, mutate, update, destroy } = useMutation()

  async function createSettlement(eventId: string) {
    return await mutate('Failed to create settlement', (commandQueue) =>
      commandQueue.enqueue<PoolApiResponse>('POST', '/settlements', {
        event_id: eventId,
      })
    )
  }

  async function deleteSettlement(id: string) {
    return await destroy(
      'Failed to delete settlement',
      'settlement',
      id,
      (commandQueue) => commandQueue.enqueue('DELETE', `/settlements/${id}`)
    )
  }

  async function markTransferPaid(transferId: string, paid: boolean) {
    await update(
      'Failed to update transfer',
      'settlementTransfer',
      transferId,
      { paidAt: paid ? new Date().toISOString() : null },
      (commandQueue) =>
        commandQueue.enqueue<PoolApiResponse>(
          'PUT',
          `/settlements/transfers/${transferId}`,
          { paid }
        )
    )
  }

  function $reset() {
    loading.value = false
    error.value = null
  }

  return {
    loading,
    error,
    createSettlement,
    deleteSettlement,
    markTransferPaid,
    $reset,
  }
})
