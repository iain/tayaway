import { defineStore } from 'pinia'
import { useMutation } from '@/composables/useMutation'
import { useObjectPoolStore } from './objectPool'
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
    await destroy(
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

  /**
   * Marks every underlying per-event transfer in a netted pair as paid in
   * one atomic server call. Used by the workspace-level Settle Up page.
   *
   * Optimistic state is added to *every* underlying transfer at once and
   * rolled back together on rejection — useMutation.update's single-object
   * shape doesn't fit, so we manage pending IDs directly.
   */
  async function markNetPaid(args: {
    workspaceId: string
    counterpartyUserId: string
    expectedAmount: number
    underlyingTransferIds: string[]
  }) {
    const pool = useObjectPoolStore()
    const optimisticPaidAt = new Date().toISOString()
    const pendingIds = args.underlyingTransferIds.map((id) =>
      pool.addPending('settlementTransfer', id, { paidAt: optimisticPaidAt })
    )

    try {
      await mutate('Failed to settle up', (commandQueue) =>
        commandQueue.enqueue<PoolApiResponse>(
          'PUT',
          `/settlements/net-transfers/mark-paid?workspace_id=${encodeURIComponent(args.workspaceId)}`,
          {
            counterparty: args.counterpartyUserId,
            expected_amount: args.expectedAmount,
          }
        )
      )
    } catch (e) {
      // mutate() swallows CommandQueuedError into a queued: true return; any
      // error reaching this catch is a real server rejection (4xx/5xx), so
      // roll the optimistic state back.
      for (const id of pendingIds) pool.removePending(id)
      throw e
    }
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
    markNetPaid,
    $reset,
  }
})
