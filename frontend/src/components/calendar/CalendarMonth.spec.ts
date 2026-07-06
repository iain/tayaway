import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import CalendarMonth from './CalendarMonth.vue'

// July 2026 (month is 0-indexed).
function mountMonth(selectedDates: string[] = []) {
  return mount(CalendarMonth, {
    props: {
      year: 2026,
      month: 6,
      selectedStart: null,
      selectedEnd: null,
      hoverDate: null,
      selectedDates,
    },
  })
}

const day = (iso: string) => `[data-testid="calendar-day-${iso}"]`

describe('CalendarMonth multi-select', () => {
  it('emits select (toggle) on a plain click', async () => {
    const w = mountMonth([])
    await w.get(day('2026-07-03')).trigger('click')

    expect(w.emitted('select')?.[0]).toEqual(['2026-07-03'])
    expect(w.emitted('selectRange')).toBeFalsy()
  })

  it('emits selectRange from the anchor when shift-clicking a later day', async () => {
    const w = mountMonth([])
    await w.get(day('2026-07-03')).trigger('click')
    await w.get(day('2026-07-06')).trigger('click', { shiftKey: true })

    expect(w.emitted('selectRange')?.[0]).toEqual(['2026-07-03', '2026-07-06'])
  })

  it('orders the range regardless of click direction', async () => {
    const w = mountMonth([])
    await w.get(day('2026-07-06')).trigger('click')
    await w.get(day('2026-07-03')).trigger('click', { shiftKey: true })

    // Emitted anchor-first; the parent normalises order.
    expect(w.emitted('selectRange')?.[0]).toEqual(['2026-07-06', '2026-07-03'])
  })

  it('falls back to select when shift-clicking without a prior anchor', async () => {
    const w = mountMonth([])
    await w.get(day('2026-07-03')).trigger('click', { shiftKey: true })

    expect(w.emitted('selectRange')).toBeFalsy()
    expect(w.emitted('select')?.[0]).toEqual(['2026-07-03'])
  })
})

describe('CalendarMonth multi-select — merged pills', () => {
  it('rounds only the ends of a run of adjacent days, and isolates single days', () => {
    // A 3-day run (Jul 3-5) plus an isolated day (Jul 7, gap on Jul 6).
    const w = mountMonth([
      '2026-07-03',
      '2026-07-04',
      '2026-07-05',
      '2026-07-07',
    ])
    const classesFor = (iso: string) => w.get(day(iso)).classes()

    // Run start: rounded on the left only.
    expect(classesFor('2026-07-03')).toContain('rounded-l-full')
    expect(classesFor('2026-07-03')).not.toContain('rounded-r-full')
    expect(classesFor('2026-07-03')).not.toContain('rounded-full')

    // Run middle: flat, so it merges with both neighbours.
    expect(classesFor('2026-07-04')).not.toContain('rounded-l-full')
    expect(classesFor('2026-07-04')).not.toContain('rounded-r-full')
    expect(classesFor('2026-07-04')).not.toContain('rounded-full')

    // Run end: rounded on the right only.
    expect(classesFor('2026-07-05')).toContain('rounded-r-full')
    expect(classesFor('2026-07-05')).not.toContain('rounded-l-full')

    // Isolated day: a full circle.
    expect(classesFor('2026-07-07')).toContain('rounded-full')
  })

  it('fills every selected day regardless of position in the run', () => {
    const w = mountMonth(['2026-07-03', '2026-07-04'])
    expect(w.get(day('2026-07-03')).classes()).toContain('bg-rose-500')
    expect(w.get(day('2026-07-04')).classes()).toContain('bg-rose-500')
    // An unselected day is not filled.
    expect(w.get(day('2026-07-06')).classes()).not.toContain('bg-rose-500')
  })
})
