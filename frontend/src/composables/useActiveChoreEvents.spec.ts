// Pin a far-from-UTC zone (UTC+14, no DST) so "today" is read from local
// calendar parts, not the UTC day. Node re-reads TZ for each Date operation.
// Declared locally because @types/node isn't in the test tsconfig.
declare const process: { env: Record<string, string> }
process.env.TZ = 'Pacific/Kiritimati'

import { describe, it, expect, beforeEach } from 'vitest'
import { ref } from 'vue'
import { createPinia, setActivePinia } from 'pinia'
import { useObjectPoolStore } from '@/stores/objectPool'
import { makeEvent, seedPool } from '@/test/factories'
import { useActiveChoreEvents } from './useActiveChoreEvents'

const NOW = () => ref(new Date('2026-06-15T12:00:00.000Z'))

let pool: ReturnType<typeof useObjectPoolStore>

describe('useActiveChoreEvents', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    pool = useObjectPoolStore()
  })

  it('returns the event under way today', () => {
    seedPool(
      pool,
      makeEvent({
        id: 'evt-now',
        name: 'Alpine Week',
        startDate: '2026-06-14',
        endDate: '2026-06-17',
      })
    )

    const { activeEvents } = useActiveChoreEvents(NOW())

    expect(activeEvents.value.map((e) => e.id)).toEqual(['evt-now'])
  })

  it('returns every overlapping event, soonest-ending first', () => {
    seedPool(
      pool,
      makeEvent({
        id: 'evt-late',
        startDate: '2026-06-10',
        endDate: '2026-06-20',
      }),
      makeEvent({
        id: 'evt-early',
        startDate: '2026-06-15',
        endDate: '2026-06-16',
      })
    )

    const { activeEvents } = useActiveChoreEvents(NOW())

    expect(activeEvents.value.map((e) => e.id)).toEqual([
      'evt-early',
      'evt-late',
    ])
  })

  it('falls back to the next upcoming event when none is under way', () => {
    seedPool(
      pool,
      makeEvent({
        id: 'evt-far',
        startDate: '2026-07-01',
        endDate: '2026-07-05',
      }),
      makeEvent({
        id: 'evt-soon',
        startDate: '2026-06-20',
        endDate: '2026-06-22',
      }),
      makeEvent({
        id: 'evt-past',
        startDate: '2026-06-01',
        endDate: '2026-06-03',
      })
    )

    const { activeEvents } = useActiveChoreEvents(NOW())

    expect(activeEvents.value.map((e) => e.id)).toEqual(['evt-soon'])
  })

  it('prefers a current event over an upcoming one', () => {
    seedPool(
      pool,
      makeEvent({
        id: 'evt-now',
        startDate: '2026-06-14',
        endDate: '2026-06-16',
      }),
      makeEvent({
        id: 'evt-soon',
        startDate: '2026-06-20',
        endDate: '2026-06-22',
      })
    )

    const { activeEvents } = useActiveChoreEvents(NOW())

    expect(activeEvents.value.map((e) => e.id)).toEqual(['evt-now'])
  })

  // The NOW instant is 12:00Z, which in UTC+14 is already the next calendar
  // day locally: local today is 2026-06-16 while the UTC day is 2026-06-15.
  // Classifying on the UTC day would keep an event that ended local-yesterday
  // "under way" and hide one starting local-today — the timezone bug this
  // guards against.
  it('classifies by the local calendar day, not the UTC day', () => {
    seedPool(
      pool,
      makeEvent({
        id: 'evt-ended-yesterday',
        startDate: '2026-06-13',
        endDate: '2026-06-15',
      }),
      makeEvent({
        id: 'evt-starts-today',
        startDate: '2026-06-16',
        endDate: '2026-06-18',
      })
    )

    const { activeEvents } = useActiveChoreEvents(NOW())

    expect(activeEvents.value.map((e) => e.id)).toEqual(['evt-starts-today'])
  })

  it('ignores events that are still date-polling and past events', () => {
    seedPool(
      pool,
      makeEvent({ id: 'evt-polling', startDate: null, endDate: null }),
      makeEvent({
        id: 'evt-past',
        startDate: '2026-06-01',
        endDate: '2026-06-03',
      })
    )

    const { activeEvents } = useActiveChoreEvents(NOW())

    expect(activeEvents.value).toEqual([])
  })
})
