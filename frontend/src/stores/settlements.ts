import { defineStore } from 'pinia'
import { nowIso } from '@/utils/date'
import { useMutation } from '@/composables/useMutation'
import { useObjectPoolStore } from './objectPool'
import { useAuthStore } from './auth'
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
      { paidAt: paid ? nowIso() : null },
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
    const auth = useAuthStore()
    const optimisticPaidAt = nowIso()
    // Stamp paidByUserId optimistically so the row jumps straight into
    // "Recently settled" with the right "Marked by you" attribution; the
    // server is still authoritative once the response lands.
    const pendingIds = args.underlyingTransferIds.map((id) =>
      pool.addPending('settlementTransfer', id, {
        paidAt: optimisticPaidAt,
        paidByUserId: auth.currentUserId,
      })
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

  /**
   * Reverses a workspace-level mark-paid for a counterparty pair, clearing
   * paid_at on every transfer the caller passes (server filters strictly to
   * matching workspace + pair so over-broad lists are safe). Optimistic
   * pending updates flip paid_at to null on each row; the import on success
   * cleans them up via the same updated_at-ordering rule importObjects uses.
   */
  async function markNetUnpaid(args: {
    workspaceId: string
    counterpartyUserId: string
    underlyingTransferIds: string[]
  }) {
    const pool = useObjectPoolStore()
    const pendingIds = args.underlyingTransferIds.map((id) =>
      pool.addPending('settlementTransfer', id, {
        paidAt: null,
        paidByUserId: null,
      })
    )

    try {
      await mutate('Failed to unmark settlement', (commandQueue) =>
        commandQueue.enqueue<PoolApiResponse>(
          'PUT',
          `/settlements/net-transfers/mark-unpaid?workspace_id=${encodeURIComponent(args.workspaceId)}`,
          {
            counterparty: args.counterpartyUserId,
            transfer_ids: args.underlyingTransferIds,
          }
        )
      )
    } catch (e) {
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
    markNetUnpaid,
    $reset,
  }
})
