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
