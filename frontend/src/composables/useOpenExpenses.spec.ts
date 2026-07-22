import { describe, it, expect, beforeEach } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useObjectPoolStore } from '@/stores/objectPool'
import {
  makeEvent,
  makeExpense,
  makeSettlement,
  makeSettlementTransfer,
  seedPool,
} from '@/test/factories'
import { useOpenExpenses } from './useOpenExpenses'

describe('useOpenExpenses', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  it('counts an expense that was never settled as open', () => {
    const pool = useObjectPoolStore()
    seedPool(
      pool,
      makeEvent({ id: 'evt-1' }),
      makeExpense({ id: 'exp-1', eventId: 'evt-1', settlementId: null })
    )

    const { hasOpenExpenses } = useOpenExpenses()

    expect(hasOpenExpenses('evt-1')).toBe(true)
  })

  it('counts a settled but unpaid transfer as open', () => {
    const pool = useObjectPoolStore()
    seedPool(
      pool,
      makeEvent({ id: 'evt-1' }),
      makeExpense({ id: 'exp-1', eventId: 'evt-1', settlementId: 'settle-1' }),
      makeSettlement({ id: 'settle-1', eventId: 'evt-1' }),
      makeSettlementTransfer({ settlementId: 'settle-1', paidAt: null })
    )

    const { hasOpenExpenses } = useOpenExpenses()

    expect(hasOpenExpenses('evt-1')).toBe(true)
  })

  it('is closed once every expense is settled and every transfer paid', () => {
    const pool = useObjectPoolStore()
    seedPool(
      pool,
      makeEvent({ id: 'evt-1' }),
      makeExpense({ id: 'exp-1', eventId: 'evt-1', settlementId: 'settle-1' }),
      makeSettlement({ id: 'settle-1', eventId: 'evt-1' }),
      makeSettlementTransfer({
        settlementId: 'settle-1',
        paidAt: '2026-06-01T10:00:00.000Z',
      })
    )

    const { hasOpenExpenses } = useOpenExpenses()

    expect(hasOpenExpenses('evt-1')).toBe(false)
  })

  it('ignores superseded transfers, which no longer represent a debt', () => {
    const pool = useObjectPoolStore()
    seedPool(
      pool,
      makeEvent({ id: 'evt-1' }),
      makeExpense({ id: 'exp-1', eventId: 'evt-1', settlementId: 'settle-1' }),
      makeSettlement({ id: 'settle-1', eventId: 'evt-1' }),
      makeSettlementTransfer({
        settlementId: 'settle-1',
        paidAt: null,
        supersededAt: '2026-06-01T10:00:00.000Z',
      })
    )

    const { hasOpenExpenses } = useOpenExpenses()

    expect(hasOpenExpenses('evt-1')).toBe(false)
  })

  it('treats an event with no expenses at all as closed', () => {
    const pool = useObjectPoolStore()
    seedPool(pool, makeEvent({ id: 'evt-1' }))

    const { hasOpenExpenses } = useOpenExpenses()

    expect(hasOpenExpenses('evt-1')).toBe(false)
  })
})
