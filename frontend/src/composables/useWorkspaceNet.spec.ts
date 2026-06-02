import { Scope } from '@/api/scope'
import { describe, it, expect, beforeEach } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useAuthStore } from '@/stores/auth'
import { useWorkspaceStore } from '@/stores/workspace'
import { useWorkspaceNet } from './useWorkspaceNet'
import {
  makeEvent,
  makeSettlement,
  makeSettlementTransfer,
  makeWorkspace,
} from '@/test/factories'

// Wires up the three stores `useWorkspaceNet` reads from. The composable
// derives everything from the pool, so each test seeds whichever objects it
// needs and relies on these helpers for the viewer/workspace identity.
function setViewer(userId: string | null): void {
  // $patch is the supported Pinia way to set state without going through an
  // action — keeps the spec sturdy if the auth store ever gains a setter.
  useAuthStore().$patch({
    user: userId
      ? {
          id: userId,
          email: 'viewer@example.com',
          name: 'Viewer',
          iban: null,
        }
      : null,
  })
}

function setWorkspace(workspaceId: string): void {
  useWorkspaceStore().currentWorkspaceId = workspaceId
}

describe('useWorkspaceNet', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    setViewer('user-viewer')
    setWorkspace('ws-1')
    const pool = useObjectPoolStore()
    pool.importObjects([makeWorkspace({ id: 'ws-1' })], {
      scope: Scope.workspace('test'),
    })
  })

  it('returns no suggestions when the pool is empty', () => {
    const { netSettlements } = useWorkspaceNet()
    expect(netSettlements.value).toEqual([])
  })

  it('returns no suggestions when the viewer or workspace is unset', () => {
    setViewer(null)

    const { netSettlements } = useWorkspaceNet()
    expect(netSettlements.value).toEqual([])
  })

  it('nets opposite-direction transfers across two events into one card', () => {
    const pool = useObjectPoolStore()
    pool.importObjects(
      [
        makeEvent({ id: 'evt-1', workspaceId: 'ws-1', name: 'Cabin' }),
        makeEvent({ id: 'evt-2', workspaceId: 'ws-1', name: 'Bowling' }),
        makeSettlement({ id: 'set-1', eventId: 'evt-1' }),
        makeSettlement({ id: 'set-2', eventId: 'evt-2' }),
        makeSettlementTransfer({
          id: 't-1',
          settlementId: 'set-1',
          fromUserId: 'user-viewer',
          toUserId: 'user-other',
          amount: 50,
        }),
        makeSettlementTransfer({
          id: 't-2',
          settlementId: 'set-2',
          fromUserId: 'user-other',
          toUserId: 'user-viewer',
          amount: 10,
        }),
      ],
      { scope: Scope.workspace('test') }
    )

    const { netSettlements } = useWorkspaceNet()

    expect(netSettlements.value).toHaveLength(1)
    const net = netSettlements.value[0]!
    expect(net.counterpartyUserId).toBe('user-other')
    expect(net.direction).toBe('owe')
    expect(net.amount).toBe(40)
    expect(net.underlyingTransferIds).toEqual(
      expect.arrayContaining(['t-1', 't-2'])
    )
    expect(net.breakdown).toHaveLength(2)
  })

  it('flags counter-direction transfers in the breakdown', () => {
    const pool = useObjectPoolStore()
    pool.importObjects(
      [
        makeEvent({ id: 'evt-1', workspaceId: 'ws-1' }),
        makeEvent({ id: 'evt-2', workspaceId: 'ws-1' }),
        makeSettlement({ id: 'set-1', eventId: 'evt-1' }),
        makeSettlement({ id: 'set-2', eventId: 'evt-2' }),
        makeSettlementTransfer({
          id: 't-1',
          settlementId: 'set-1',
          fromUserId: 'user-viewer',
          toUserId: 'user-other',
          amount: 50,
        }),
        makeSettlementTransfer({
          id: 't-2',
          settlementId: 'set-2',
          fromUserId: 'user-other',
          toUserId: 'user-viewer',
          amount: 10,
        }),
      ],
      { scope: Scope.workspace('test') }
    )

    const { netSettlements } = useWorkspaceNet()
    const breakdown = netSettlements.value[0]!.breakdown
    const dominant = breakdown.find((b) => b.transfer.id === 't-1')!
    const counter = breakdown.find((b) => b.transfer.id === 't-2')!
    expect(dominant.isDominantDirection).toBe(true)
    expect(counter.isDominantDirection).toBe(false)
  })

  it('sums same-direction transfers across events', () => {
    const pool = useObjectPoolStore()
    pool.importObjects(
      [
        makeEvent({ id: 'evt-1', workspaceId: 'ws-1' }),
        makeEvent({ id: 'evt-2', workspaceId: 'ws-1' }),
        makeSettlement({ id: 'set-1', eventId: 'evt-1' }),
        makeSettlement({ id: 'set-2', eventId: 'evt-2' }),
        makeSettlementTransfer({
          id: 't-1',
          settlementId: 'set-1',
          fromUserId: 'user-viewer',
          toUserId: 'user-other',
          amount: 25,
        }),
        makeSettlementTransfer({
          id: 't-2',
          settlementId: 'set-2',
          fromUserId: 'user-viewer',
          toUserId: 'user-other',
          amount: 15,
        }),
      ],
      { scope: Scope.workspace('test') }
    )

    const { netSettlements } = useWorkspaceNet()
    expect(netSettlements.value[0]!.amount).toBe(40)
    expect(netSettlements.value[0]!.direction).toBe('owe')
  })

  it('drops pairs that cancel exactly', () => {
    const pool = useObjectPoolStore()
    pool.importObjects(
      [
        makeEvent({ id: 'evt-1', workspaceId: 'ws-1' }),
        makeEvent({ id: 'evt-2', workspaceId: 'ws-1' }),
        makeSettlement({ id: 'set-1', eventId: 'evt-1' }),
        makeSettlement({ id: 'set-2', eventId: 'evt-2' }),
        makeSettlementTransfer({
          id: 't-1',
          settlementId: 'set-1',
          fromUserId: 'user-viewer',
          toUserId: 'user-other',
          amount: 30,
        }),
        makeSettlementTransfer({
          id: 't-2',
          settlementId: 'set-2',
          fromUserId: 'user-other',
          toUserId: 'user-viewer',
          amount: 30,
        }),
      ],
      { scope: Scope.workspace('test') }
    )

    const { netSettlements } = useWorkspaceNet()
    expect(netSettlements.value).toEqual([])
  })

  it('ignores paid and superseded transfers', () => {
    const pool = useObjectPoolStore()
    pool.importObjects(
      [
        makeEvent({ id: 'evt-1', workspaceId: 'ws-1' }),
        makeSettlement({ id: 'set-1', eventId: 'evt-1' }),
        makeSettlementTransfer({
          id: 't-paid',
          settlementId: 'set-1',
          fromUserId: 'user-viewer',
          toUserId: 'user-other',
          amount: 50,
          paidAt: '2026-04-01T00:00:00.000Z',
        }),
        makeSettlementTransfer({
          id: 't-super',
          settlementId: 'set-1',
          fromUserId: 'user-viewer',
          toUserId: 'user-other',
          amount: 30,
          supersededAt: '2026-04-01T00:00:00.000Z',
        }),
      ],
      { scope: Scope.workspace('test') }
    )

    const { netSettlements } = useWorkspaceNet()
    expect(netSettlements.value).toEqual([])
  })

  it("hides pairs the viewer isn't part of", () => {
    const pool = useObjectPoolStore()
    pool.importObjects(
      [
        makeEvent({ id: 'evt-1', workspaceId: 'ws-1' }),
        makeSettlement({ id: 'set-1', eventId: 'evt-1' }),
        makeSettlementTransfer({
          id: 't-1',
          settlementId: 'set-1',
          fromUserId: 'user-a',
          toUserId: 'user-b',
          amount: 50,
        }),
      ],
      { scope: Scope.workspace('test') }
    )

    const { netSettlements } = useWorkspaceNet()
    expect(netSettlements.value).toEqual([])
  })

  it('scopes to the current workspace', () => {
    const pool = useObjectPoolStore()
    pool.importObjects(
      [
        makeEvent({ id: 'evt-other', workspaceId: 'ws-other' }),
        makeSettlement({ id: 'set-1', eventId: 'evt-other' }),
        makeSettlementTransfer({
          id: 't-1',
          settlementId: 'set-1',
          fromUserId: 'user-viewer',
          toUserId: 'user-other',
          amount: 50,
        }),
      ],
      { scope: Scope.workspace('test') }
    )

    const { netSettlements } = useWorkspaceNet()
    expect(netSettlements.value).toEqual([])
  })

  it('flips direction when the viewer is the net creditor', () => {
    const pool = useObjectPoolStore()
    pool.importObjects(
      [
        makeEvent({ id: 'evt-1', workspaceId: 'ws-1' }),
        makeSettlement({ id: 'set-1', eventId: 'evt-1' }),
        makeSettlementTransfer({
          id: 't-1',
          settlementId: 'set-1',
          fromUserId: 'user-other',
          toUserId: 'user-viewer',
          amount: 25,
        }),
      ],
      { scope: Scope.workspace('test') }
    )

    const { netSettlements } = useWorkspaceNet()
    expect(netSettlements.value[0]!.direction).toBe('owed')
    expect(netSettlements.value[0]!.amount).toBe(25)
  })

  it('sorts suggestions by amount descending', () => {
    const pool = useObjectPoolStore()
    pool.importObjects(
      [
        makeEvent({ id: 'evt-1', workspaceId: 'ws-1' }),
        makeSettlement({ id: 'set-1', eventId: 'evt-1' }),
        makeSettlementTransfer({
          id: 't-small',
          settlementId: 'set-1',
          fromUserId: 'user-viewer',
          toUserId: 'user-a',
          amount: 5,
        }),
        makeSettlementTransfer({
          id: 't-big',
          settlementId: 'set-1',
          fromUserId: 'user-viewer',
          toUserId: 'user-b',
          amount: 80,
        }),
      ],
      { scope: Scope.workspace('test') }
    )

    const { netSettlements } = useWorkspaceNet()
    expect(netSettlements.value.map((n) => n.counterpartyUserId)).toEqual([
      'user-b',
      'user-a',
    ])
  })

  describe('recentSettlements', () => {
    it('returns empty when no transfers have paidAt within the window', () => {
      const pool = useObjectPoolStore()
      pool.importObjects(
        [
          makeEvent({ id: 'evt-1', workspaceId: 'ws-1' }),
          makeSettlement({ id: 'set-1', eventId: 'evt-1' }),
          makeSettlementTransfer({
            id: 't-1',
            settlementId: 'set-1',
            fromUserId: 'user-viewer',
            toUserId: 'user-other',
            amount: 25,
            paidAt: null,
          }),
        ],
        { scope: Scope.workspace('test') }
      )

      const { recentSettlements } = useWorkspaceNet()
      expect(recentSettlements.value).toEqual([])
    })

    it('groups recently-paid transfers between the same pair and direction', () => {
      const recent = new Date(Date.now() - 60_000).toISOString()
      const pool = useObjectPoolStore()
      pool.importObjects(
        [
          makeEvent({ id: 'evt-1', workspaceId: 'ws-1', name: 'Cabin' }),
          makeEvent({ id: 'evt-2', workspaceId: 'ws-1', name: 'Bowling' }),
          makeSettlement({ id: 'set-1', eventId: 'evt-1' }),
          makeSettlement({ id: 'set-2', eventId: 'evt-2' }),
          makeSettlementTransfer({
            id: 't-1',
            settlementId: 'set-1',
            fromUserId: 'user-viewer',
            toUserId: 'user-other',
            amount: 30,
            paidAt: recent,
            paidByUserId: 'user-viewer',
          }),
          makeSettlementTransfer({
            id: 't-2',
            settlementId: 'set-2',
            fromUserId: 'user-viewer',
            toUserId: 'user-other',
            amount: 10,
            paidAt: recent,
            paidByUserId: 'user-viewer',
          }),
        ],
        { scope: Scope.workspace('test') }
      )

      const { recentSettlements } = useWorkspaceNet()
      expect(recentSettlements.value).toHaveLength(1)
      const r = recentSettlements.value[0]!
      expect(r.direction).toBe('paid')
      expect(r.amount).toBe(40)
      expect(r.transferCount).toBe(2)
      expect(r.eventCount).toBe(2)
      expect(r.paidByUserId).toBe('user-viewer')
    })

    it('nets mixed-direction transfers within the window into one card', () => {
      const recent = new Date(Date.now() - 60_000).toISOString()
      const pool = useObjectPoolStore()
      pool.importObjects(
        [
          makeEvent({ id: 'evt-1', workspaceId: 'ws-1' }),
          makeEvent({ id: 'evt-2', workspaceId: 'ws-1' }),
          makeSettlement({ id: 'set-1', eventId: 'evt-1' }),
          makeSettlement({ id: 'set-2', eventId: 'evt-2' }),
          makeSettlementTransfer({
            id: 't-dominant',
            settlementId: 'set-1',
            fromUserId: 'user-other',
            toUserId: 'user-viewer',
            amount: 40,
            paidAt: recent,
          }),
          makeSettlementTransfer({
            id: 't-counter',
            settlementId: 'set-2',
            fromUserId: 'user-viewer',
            toUserId: 'user-other',
            amount: 15,
            paidAt: recent,
          }),
        ],
        { scope: Scope.workspace('test') }
      )

      const { recentSettlements } = useWorkspaceNet()
      expect(recentSettlements.value).toHaveLength(1)
      const r = recentSettlements.value[0]!
      expect(r.direction).toBe('received')
      expect(r.amount).toBe(25)
      expect(r.breakdown).toHaveLength(2)
      expect(
        r.breakdown.find((b) => b.transfer.id === 't-dominant')!
          .isDominantDirection
      ).toBe(true)
      expect(
        r.breakdown.find((b) => b.transfer.id === 't-counter')!
          .isDominantDirection
      ).toBe(false)
    })

    it('drops pairs where mixed directions cancel exactly', () => {
      const recent = new Date(Date.now() - 60_000).toISOString()
      const pool = useObjectPoolStore()
      pool.importObjects(
        [
          makeEvent({ id: 'evt-1', workspaceId: 'ws-1' }),
          makeSettlement({ id: 'set-1', eventId: 'evt-1' }),
          makeSettlementTransfer({
            id: 't-a',
            settlementId: 'set-1',
            fromUserId: 'user-viewer',
            toUserId: 'user-other',
            amount: 20,
            paidAt: recent,
          }),
          makeSettlementTransfer({
            id: 't-b',
            settlementId: 'set-1',
            fromUserId: 'user-other',
            toUserId: 'user-viewer',
            amount: 20,
            paidAt: recent,
          }),
        ],
        { scope: Scope.workspace('test') }
      )

      const { recentSettlements } = useWorkspaceNet()
      expect(recentSettlements.value).toEqual([])
    })

    it('drops transfers paid before the recency window', () => {
      const old = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString()
      const pool = useObjectPoolStore()
      pool.importObjects(
        [
          makeEvent({ id: 'evt-1', workspaceId: 'ws-1' }),
          makeSettlement({ id: 'set-1', eventId: 'evt-1' }),
          makeSettlementTransfer({
            id: 't-old',
            settlementId: 'set-1',
            fromUserId: 'user-viewer',
            toUserId: 'user-other',
            amount: 50,
            paidAt: old,
          }),
        ],
        { scope: Scope.workspace('test') }
      )

      const { recentSettlements } = useWorkspaceNet()
      expect(recentSettlements.value).toEqual([])
    })

    it('orders by latestPaidAt descending', () => {
      const newer = new Date(Date.now() - 60_000).toISOString()
      const older = new Date(Date.now() - 60 * 60_000).toISOString()
      const pool = useObjectPoolStore()
      pool.importObjects(
        [
          makeEvent({ id: 'evt-1', workspaceId: 'ws-1' }),
          makeSettlement({ id: 'set-1', eventId: 'evt-1' }),
          makeSettlementTransfer({
            id: 't-old-pair',
            settlementId: 'set-1',
            fromUserId: 'user-viewer',
            toUserId: 'user-a',
            amount: 10,
            paidAt: older,
          }),
          makeSettlementTransfer({
            id: 't-new-pair',
            settlementId: 'set-1',
            fromUserId: 'user-viewer',
            toUserId: 'user-b',
            amount: 10,
            paidAt: newer,
          }),
        ],
        { scope: Scope.workspace('test') }
      )

      const { recentSettlements } = useWorkspaceNet()
      expect(recentSettlements.value.map((r) => r.counterpartyUserId)).toEqual([
        'user-b',
        'user-a',
      ])
    })
  })

  it('produces a stable id regardless of viewer/counterparty ordering', () => {
    const pool = useObjectPoolStore()
    pool.importObjects(
      [
        makeEvent({ id: 'evt-1', workspaceId: 'ws-1' }),
        makeSettlement({ id: 'set-1', eventId: 'evt-1' }),
        makeSettlementTransfer({
          id: 't-1',
          settlementId: 'set-1',
          fromUserId: 'user-viewer',
          toUserId: 'user-other',
          amount: 25,
        }),
      ],
      { scope: Scope.workspace('test') }
    )

    const { netSettlements } = useWorkspaceNet()
    const expectedId = ['user-viewer', 'user-other'].sort().join(':')
    expect(netSettlements.value[0]!.id).toBe(expectedId)
  })
})
