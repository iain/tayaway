import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import ManageChoresSheet from './ManageChoresSheet.vue'
import { makeChore } from '@/test/factories'

const updateChoreSpy = vi.fn().mockResolvedValue(undefined)
const deleteChoreSpy = vi.fn().mockResolvedValue(undefined)

vi.mock('@/stores/choreRosters', () => ({
  useChoreRostersStore: () => ({
    updateChore: updateChoreSpy,
    deleteChore: deleteChoreSpy,
  }),
}))

function mountSheet() {
  return mount(ManageChoresSheet, {
    props: {
      open: true,
      rosterId: 'r1',
      chores: [
        makeChore({ id: 'a', name: 'Cooking', position: 1, time: '18:00' }),
        makeChore({ id: 'b', name: 'Washing up', position: 2 }),
        makeChore({ id: 'c', name: 'Shopping', position: 3 }),
      ],
    },
  })
}

describe('ManageChoresSheet', () => {
  beforeEach(() => {
    updateChoreSpy.mockClear()
    deleteChoreSpy.mockClear()
  })

  it('renders a row for every chore in position order', () => {
    const rows = mountSheet().findAll('[data-chore-id]')
    expect(rows.map((r) => r.attributes('data-chore-id'))).toEqual([
      'a',
      'b',
      'c',
    ])
  })

  it('moves a chore up past its neighbour', async () => {
    const sheet = mountSheet()
    await sheet.get('[data-testid="move-up-b"]').trigger('click')
    expect(updateChoreSpy).toHaveBeenCalledWith('r1', 'b', { position: 0 })
  })

  it('disables reordering at the ends of the list', () => {
    const sheet = mountSheet()
    expect(
      sheet.get('[data-testid="move-up-a"]').attributes('disabled')
    ).toBeDefined()
    expect(
      sheet.get('[data-testid="move-down-c"]').attributes('disabled')
    ).toBeDefined()
  })

  it('saves a new time when the time input changes', async () => {
    const sheet = mountSheet()
    const input = sheet.get('[data-chore-id="b"]').get('input[type="time"]')
    await input.setValue('07:15')
    await input.trigger('change')
    expect(updateChoreSpy).toHaveBeenCalledWith('r1', 'b', { time: '07:15' })
  })

  it('clears the time when the input is emptied', async () => {
    const sheet = mountSheet()
    const input = sheet.get('[data-chore-id="a"]').get('input[type="time"]')
    await input.setValue('')
    await input.trigger('change')
    expect(updateChoreSpy).toHaveBeenCalledWith('r1', 'a', { time: null })
  })

  it('deletes a chore only after an inline confirm', async () => {
    const sheet = mountSheet()

    await sheet.get('[data-testid="delete-b"]').trigger('click')
    expect(deleteChoreSpy).not.toHaveBeenCalled()

    // A confirm affordance is now shown; the confirm button commits.
    await sheet.get('[data-testid="confirm-delete-b"]').trigger('click')
    expect(deleteChoreSpy).toHaveBeenCalledWith('r1', 'b')
  })

  it('cancelling the confirm keeps the chore', async () => {
    const sheet = mountSheet()
    await sheet.get('[data-testid="delete-c"]').trigger('click')
    await sheet.get('[data-testid="cancel-delete-c"]').trigger('click')
    expect(deleteChoreSpy).not.toHaveBeenCalled()
    expect(sheet.find('[data-testid="confirm-delete-c"]').exists()).toBe(false)
  })
})
