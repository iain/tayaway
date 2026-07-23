import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { ref } from 'vue'
import { createPinia, setActivePinia } from 'pinia'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useWorkspaceStore } from '@/stores/workspace'
import { makeEvent, makeExpense, seedPool } from '@/test/factories'
import { useFocusedEvent } from './useFocusedEvent'

const TODAY = new Date('2026-06-02T12:00:00Z')

describe('useFocusedEvent', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    localStorage.clear()
    vi.useFakeTimers()
    vi.setSystemTime(TODAY)
    useWorkspaceStore().currentWorkspaceId = 'ws-1'
    // The pin is module-level state that outlives the Pinia instance, so it
    // resets through the public API rather than by reloading the module.
    useFocusedEvent().resetFocus()
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  it('focuses the event under way today when nothing is pinned', () => {
    const pool = useObjectPoolStore()
    seedPool(
      pool,
      makeEvent({ id: 'past', startDate: '2026-05-01', endDate: '2026-05-02' }),
      makeEvent({
        id: 'under-way',
        startDate: '2026-06-01',
        endDate: '2026-06-04',
      }),
      makeEvent({
        id: 'upcoming',
        startDate: '2026-07-01',
        endDate: '2026-07-03',
      })
    )

    const { focusedEvent } = useFocusedEvent()

    expect(focusedEvent.value?.id).toBe('under-way')
  })

  it('falls back to the next event to start when nothing is under way', () => {
    const pool = useObjectPoolStore()
    seedPool(
      pool,
      makeEvent({ id: 'past', startDate: '2026-05-01', endDate: '2026-05-02' }),
      makeEvent({
        id: 'later',
        startDate: '2026-08-01',
        endDate: '2026-08-03',
      }),
      makeEvent({ id: 'next', startDate: '2026-07-01', endDate: '2026-07-03' })
    )

    const { focusedEvent } = useFocusedEvent()

    expect(focusedEvent.value?.id).toBe('next')
  })

  it('prefers a pinned event over the derived one', () => {
    const pool = useObjectPoolStore()
    seedPool(
      pool,
      makeEvent({
        id: 'under-way',
        startDate: '2026-06-01',
        endDate: '2026-06-04',
      }),
      makeEvent({
        id: 'next-summer',
        startDate: '2026-08-01',
        endDate: '2026-08-10',
      })
    )

    const { focusedEvent, pinEvent } = useFocusedEvent()
    pinEvent('next-summer')

    expect(focusedEvent.value?.id).toBe('next-summer')
  })

  it('keeps a finished event pinned while its expenses are still open', () => {
    const pool = useObjectPoolStore()
    seedPool(
      pool,
      makeEvent({ id: 'rome', startDate: '2026-05-20', endDate: '2026-05-27' }),
      makeExpense({ id: 'exp-1', eventId: 'rome', settlementId: null }),
      makeEvent({
        id: 'under-way',
        startDate: '2026-06-01',
        endDate: '2026-06-04',
      })
    )

    const { focusedEvent, pinEvent } = useFocusedEvent()
    pinEvent('rome')

    expect(focusedEvent.value?.id).toBe('rome')
  })

  it('drops the pin once the event has ended and the books are closed', () => {
    const pool = useObjectPoolStore()
    seedPool(
      pool,
      makeEvent({ id: 'rome', startDate: '2026-05-20', endDate: '2026-05-27' }),
      makeEvent({
        id: 'under-way',
        startDate: '2026-06-01',
        endDate: '2026-06-04',
      })
    )

    const { focusedEvent, pinEvent } = useFocusedEvent()
    pinEvent('rome')

    expect(focusedEvent.value?.id).toBe('under-way')
  })

  it('drops a long-finished pin even when an expense was never settled', () => {
    const pool = useObjectPoolStore()
    seedPool(
      pool,
      // Ended well over FOCUS_MAX_DAYS_AFTER_END ago, with one forgotten
      // expense nobody is ever going to settle.
      makeEvent({
        id: 'zombie',
        startDate: '2025-08-01',
        endDate: '2025-08-10',
      }),
      makeExpense({ id: 'exp-1', eventId: 'zombie', settlementId: null }),
      makeEvent({
        id: 'under-way',
        startDate: '2026-06-01',
        endDate: '2026-06-04',
      })
    )

    const { focusedEvent, pinEvent } = useFocusedEvent()
    pinEvent('zombie')

    expect(focusedEvent.value?.id).toBe('under-way')
  })

  it('survives a reload, so focus is not re-picked on every visit', () => {
    const pool = useObjectPoolStore()
    seedPool(
      pool,
      makeEvent({
        id: 'under-way',
        startDate: '2026-06-01',
        endDate: '2026-06-04',
      }),
      makeEvent({
        id: 'next-summer',
        startDate: '2026-08-01',
        endDate: '2026-08-10',
      })
    )
    useFocusedEvent().pinEvent('next-summer')

    // A fresh Pinia stands in for a reload; the pin is read back from storage.
    setActivePinia(createPinia())
    useWorkspaceStore().currentWorkspaceId = 'ws-1'
    const reloadedPool = useObjectPoolStore()
    seedPool(
      reloadedPool,
      makeEvent({
        id: 'under-way',
        startDate: '2026-06-01',
        endDate: '2026-06-04',
      }),
      makeEvent({
        id: 'next-summer',
        startDate: '2026-08-01',
        endDate: '2026-08-10',
      })
    )

    expect(useFocusedEvent().focusedEvent.value?.id).toBe('next-summer')
  })

  it('clears focus entirely when the user unfocuses', () => {
    const pool = useObjectPoolStore()
    seedPool(
      pool,
      makeEvent({
        id: 'under-way',
        startDate: '2026-06-01',
        endDate: '2026-06-04',
      }),
      makeEvent({
        id: 'next-summer',
        startDate: '2026-08-01',
        endDate: '2026-08-10',
      })
    )

    const { focusedEvent, unfocusEvent } = useFocusedEvent()
    unfocusEvent()

    expect(focusedEvent.value).toBeNull()
  })

  // The reason unfocusing records *which* event it silenced: it expires on
  // its own rather than leaving the workspace permanently quiet.
  it('takes focus back up once the dismissed event is no longer the one derived', () => {
    const pool = useObjectPoolStore()
    seedPool(
      pool,
      makeEvent({
        id: 'under-way',
        startDate: '2026-06-01',
        endDate: '2026-06-04',
      }),
      makeEvent({
        id: 'next-summer',
        startDate: '2026-08-01',
        endDate: '2026-08-10',
      })
    )

    const now = ref(TODAY)
    const { focusedEvent, unfocusEvent } = useFocusedEvent(now)
    unfocusEvent()

    now.value = new Date('2026-06-05T12:00:00Z')

    expect(focusedEvent.value?.id).toBe('next-summer')
  })

  it('does not carry a pin across into another workspace', () => {
    const pool = useObjectPoolStore()
    seedPool(
      pool,
      makeEvent({
        id: 'next-summer',
        startDate: '2026-08-01',
        endDate: '2026-08-10',
      })
    )
    useFocusedEvent().pinEvent('next-summer')

    useWorkspaceStore().currentWorkspaceId = 'ws-2'
    seedPool(
      pool,
      makeEvent({
        id: 'other-ws-event',
        workspaceId: 'ws-2',
        startDate: '2026-06-01',
        endDate: '2026-06-04',
      })
    )

    expect(useFocusedEvent().focusedEvent.value?.id).toBe('other-ws-event')
  })
})
