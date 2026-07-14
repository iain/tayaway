import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import ChoreRosterGrid from './ChoreRosterGrid.vue'
import { makeChore } from '@/test/factories'

const updateChoreSpy = vi.fn().mockResolvedValue(undefined)

vi.mock('@/stores/choreRosters', () => ({
  useChoreRostersStore: () => ({ updateChore: updateChoreSpy }),
}))

// SortableJS needs a real DOM; the keyboard path under test doesn't, so stub it.
vi.mock('vue-draggable-plus', () => ({ useDraggable: () => ({}) }))

describe('ChoreRosterGrid keyboard reorder', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    updateChoreSpy.mockClear()
  })

  function mountGrid() {
    return mount(ChoreRosterGrid, {
      props: {
        chores: [
          makeChore({ id: 'a', name: 'A', position: 1 }),
          makeChore({ id: 'b', name: 'B', position: 2 }),
          makeChore({ id: 'c', name: 'C', position: 3 }),
        ],
        assignments: [],
        dates: ['2026-01-01'],
        members: [],
        attendances: [],
        rosterId: 'roster-1',
        currentUserId: null,
        today: '2026-01-01',
      },
    })
  }

  it('moves a chore right past its neighbour on ArrowRight', async () => {
    const handles = mountGrid().findAll('.chore-drag-handle')
    await handles[1].trigger('keydown', { key: 'ArrowRight' })
    expect(updateChoreSpy).toHaveBeenCalledWith('roster-1', 'b', {
      position: 4,
    })
  })

  it('moves a chore left past its neighbour on ArrowLeft', async () => {
    const handles = mountGrid().findAll('.chore-drag-handle')
    await handles[1].trigger('keydown', { key: 'ArrowLeft' })
    expect(updateChoreSpy).toHaveBeenCalledWith('roster-1', 'b', {
      position: 0,
    })
  })

  it('does nothing at the ends of the row', async () => {
    const handles = mountGrid().findAll('.chore-drag-handle')
    await handles[0].trigger('keydown', { key: 'ArrowLeft' })
    await handles[2].trigger('keydown', { key: 'ArrowRight' })
    expect(updateChoreSpy).not.toHaveBeenCalled()
  })

  it('keeps the chore name out of the reorder handle so getByText stays unique', () => {
    // The visible column header already shows the name; embedding it in the
    // handle's sr-only label duplicated e.g. "Cooking" in the DOM and broke the
    // e2e `getByText('Cooking')` grid-ready checks with a strict-mode match.
    const wrapper = mount(ChoreRosterGrid, {
      props: {
        chores: [makeChore({ id: 'a', name: 'Cooking', position: 1 })],
        assignments: [],
        dates: ['2026-01-01'],
        members: [],
        attendances: [],
        rosterId: 'roster-1',
        currentUserId: null,
        today: '2026-01-01',
      },
    })
    expect(wrapper.get('.chore-drag-handle').text()).not.toContain('Cooking')
  })

  it('announces the new position in a live region', async () => {
    const wrapper = mountGrid()
    await wrapper
      .findAll('.chore-drag-handle')[1]
      .trigger('keydown', { key: 'ArrowRight' })
    expect(wrapper.get('[role="status"]').text()).toBe(
      'B moved to position 3 of 3'
    )
  })
})
