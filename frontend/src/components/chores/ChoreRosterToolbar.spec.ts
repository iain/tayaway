import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { ref } from 'vue'
import ChoreRosterToolbar from './ChoreRosterToolbar.vue'

const isDesktop = ref(true)
vi.mock('@/composables/useMediaQuery', () => ({
  useMediaQuery: () => isDesktop,
}))

async function openMenu(
  props: { canDelete?: boolean; canClear?: boolean } = {}
) {
  const wrapper = mount(ChoreRosterToolbar, {
    props: { canClear: true, ...props },
  })
  await wrapper.get('button[aria-label="More roster actions"]').trigger('click')
  return wrapper
}

function itemLabels(wrapper: Awaited<ReturnType<typeof openMenu>>): string[] {
  return wrapper.findAll('[role="menuitem"]').map((item) => item.text().trim())
}

describe('ChoreRosterToolbar overflow menu', () => {
  beforeEach(() => {
    isDesktop.value = true
  })

  it('offers clearing to anyone who can edit, deletion only to those who can delete', async () => {
    expect(itemLabels(await openMenu({ canDelete: true }))).toEqual([
      'Clear upcoming assignments…',
      'Delete roster…',
    ])
    expect(itemLabels(await openMenu({ canDelete: false }))).toEqual([
      'Clear upcoming assignments…',
    ])
    expect(
      itemLabels(await openMenu({ canDelete: true, canClear: false }))
    ).toEqual(['Delete roster…'])
  })

  it('emits one event per chosen item', async () => {
    const wrapper = await openMenu({ canDelete: true })
    const items = wrapper.findAll('[role="menuitem"]')
    await items[0]!.trigger('click')
    expect(wrapper.emitted('clearUpcoming')).toHaveLength(1)

    await wrapper
      .get('button[aria-label="More roster actions"]')
      .trigger('click')
    const reopened = wrapper.findAll('[role="menuitem"]')
    await reopened[1]!.trigger('click')
    expect(wrapper.emitted('deleteRoster')).toHaveLength(1)
  })

  it('folds Auto-fill and Manage chores into the menu on the phone', async () => {
    isDesktop.value = false
    expect(itemLabels(await openMenu({ canDelete: true }))).toEqual([
      'Auto-fill',
      'Manage chores',
      'Clear upcoming assignments…',
      'Delete roster…',
    ])
  })
})
