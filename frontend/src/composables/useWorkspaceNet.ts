import { computed, type ComputedRef } from 'vue'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useAuthStore } from '@/stores/auth'
import { useWorkspaceStore } from '@/stores/workspace'
import type {
  PoolEvent,
  PoolSettlementTransfer,
  PoolSettlement,
} from '@/types/pool'

export interface NetSettlementBreakdown {
  transfer: PoolSettlementTransfer
  event: PoolEvent | undefined
  // True when this transfer is in the dominant direction of the net pair —
  // i.e. it adds to the net rather than offsetting it. Useful when listing
  // contributing transfers so the UI can show counter-direction rows
  // distinctly ("you're owed 10 here, but owe 50 elsewhere").
  isDominantDirection: boolean
}

export interface NetSettlement {
  // Stable id derived from the pair, suitable as a v-for key.
  id: string
  counterpartyUserId: string
  // Direction the *viewer* needs to think in: 'owe' = viewer pays, 'owed' =
  // viewer receives. Mirrors how OpenSettlementsSection splits its lists.
  direction: 'owe' | 'owed'
  amount: number
  underlyingTransferIds: string[]
  breakdown: NetSettlementBreakdown[]
  // Counts derived from breakdown, precomputed so templates don't rebuild
  // a Set on every reactive read.
  transferCount: number
  eventCount: number
}

const EPSILON = 0.005

/**
 * Nets active (non-superseded, unpaid) per-event transfers across the
 * current workspace by counterparty pair, scoped to pairs the viewer is
 * involved in. Mirrors the server-side logic in `Settlements::WorkspaceNet`
 * so the page can render instantly without a network round-trip.
 */
export function useWorkspaceNet(): {
  netSettlements: ComputedRef<NetSettlement[]>
} {
  const pool = useObjectPoolStore()
  const auth = useAuthStore()
  const workspace = useWorkspaceStore()

  const netSettlements = computed<NetSettlement[]>(() => {
    const viewerId = auth.currentUserId
    const workspaceId = workspace.currentWorkspaceId
    if (!viewerId || !workspaceId) return []

    const settlements = pool.getAll('settlement') as PoolSettlement[]
    const eventBySettlement = new Map<string, string>()
    for (const s of settlements) {
      eventBySettlement.set(s.id, s.eventId)
    }

    const eventIdsInWorkspace = new Set(
      pool
        .getAll('event')
        .filter((e) => e.workspaceId === workspaceId)
        .map((e) => e.id)
    )

    type Bucket = {
      counterpartyUserId: string
      signedTotal: number
      breakdown: NetSettlementBreakdown[]
    }
    const buckets = new Map<string, Bucket>()

    for (const t of pool.getAll(
      'settlementTransfer'
    ) as PoolSettlementTransfer[]) {
      if (t.paidAt || t.supersededAt) continue
      if (!t.fromUserId || !t.toUserId) continue
      if (t.fromUserId !== viewerId && t.toUserId !== viewerId) continue

      const eventId = eventBySettlement.get(t.settlementId)
      if (!eventId || !eventIdsInWorkspace.has(eventId)) continue

      const counterpartyUserId =
        t.fromUserId === viewerId ? t.toUserId : t.fromUserId
      const signed = t.fromUserId === viewerId ? t.amount : -t.amount

      let bucket = buckets.get(counterpartyUserId)
      if (!bucket) {
        bucket = {
          counterpartyUserId,
          signedTotal: 0,
          breakdown: [],
        }
        buckets.set(counterpartyUserId, bucket)
      }
      bucket.signedTotal += signed
      bucket.breakdown.push({
        transfer: t,
        event: pool.get('event', eventId),
        // Dominant direction is determined after the loop; placeholder for now.
        isDominantDirection: false,
      })
    }

    const results: NetSettlement[] = []
    for (const bucket of buckets.values()) {
      const amount = Math.round(Math.abs(bucket.signedTotal) * 100) / 100
      if (amount < EPSILON) continue

      const direction: 'owe' | 'owed' = bucket.signedTotal > 0 ? 'owe' : 'owed'

      const breakdown = bucket.breakdown.map((b) => ({
        ...b,
        isDominantDirection:
          direction === 'owe'
            ? b.transfer.fromUserId === viewerId
            : b.transfer.toUserId === viewerId,
      }))

      // Stable, direction-agnostic key so a flip in dominant direction
      // (e.g. after a top-up) doesn't reset list animations or focus.
      const id = [viewerId, bucket.counterpartyUserId].sort().join(':')

      const eventIds = new Set<string | undefined>()
      for (const b of breakdown) eventIds.add(b.event?.id)

      results.push({
        id,
        counterpartyUserId: bucket.counterpartyUserId,
        direction,
        amount,
        underlyingTransferIds: bucket.breakdown.map((b) => b.transfer.id),
        breakdown,
        transferCount: breakdown.length,
        eventCount: eventIds.size,
      })
    }

    // Largest amounts first — surfaces the most material balance for the user.
    results.sort((a, b) => b.amount - a.amount)
    return results
  })

  return { netSettlements }
}
