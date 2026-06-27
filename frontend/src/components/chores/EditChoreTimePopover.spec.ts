import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import EditChoreTimePopover from './EditChoreTimePopover.vue'
import { makeChore } from '@/test/factories'
import type { PoolChore } from '@/types/pool'

const updateChoreSpy = vi.fn().mockResolvedValue(undefined)

vi.mock('@/stores/choreRosters', () => ({
  useChoreRostersStore: () => ({ updateChore: updateChoreSpy }),
}))

describe('EditChoreTimePopover', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    updateChoreSpy.mockClear()
  })

  function mountPopover(chore: PoolChore) {
    return mount(EditChoreTimePopover, {
      props: {
        chore,
        anchorEl: document.createElement('div'),
        rosterId: 'roster-1',
      },
    })
  }

  it('saves the time the field shows even when v-model lagged the commit', async () => {
    const wrapper = mountPopover(makeChore({ id: 'chore-1', time: null }))
    const input = wrapper.get('input[type="time"]')

    // Firefox commits a partially-typed minute (a lone "0", shown as "00") to
    // the element only on blur, firing 'change' rather than the 'input' event
    // v-model listens to — so the bound ref stays ''. Reproduce that by setting
    // the committed value without dispatching 'input', then pressing Enter.
    ;(input.element as HTMLInputElement).value = '09:00'
    await input.trigger('keydown.enter')

    expect(updateChoreSpy).toHaveBeenCalledWith('roster-1', 'chore-1', {
      time: '09:00',
    })
  })

  it('closes without saving when nothing was entered', async () => {
    const wrapper = mountPopover(makeChore({ id: 'chore-1', time: null }))

    await wrapper.get('input[type="time"]').trigger('keydown.enter')

    expect(updateChoreSpy).not.toHaveBeenCalled()
    expect(wrapper.emitted('close')).toBeTruthy()
  })
})
