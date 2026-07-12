import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { mount } from '@vue/test-utils'
import ActionMenu from './ActionMenu.vue'
import type { ActionMenuAction } from './ActionMenu.vue'

const realMatchMedia = window.matchMedia

// The global setup stubs matchMedia to always-false (mobile). Flip it per
// test to exercise the desktop dropdown branch.
function stubViewport(desktop: boolean): void {
  window.matchMedia = vi.fn().mockImplementation((query: string) => ({
    matches: desktop,
    media: query,
    onchange: null,
    addListener: vi.fn(),
    removeListener: vi.fn(),
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    dispatchEvent: vi.fn(),
  })) as unknown as typeof window.matchMedia
}

afterEach(() => {
  window.matchMedia = realMatchMedia
})

const actions: ActionMenuAction[] = [
  { key: 'rename', label: 'Rename list', testid: 'rename-action' },
  {
    key: 'delete',
    label: 'Delete list',
    danger: true,
    testid: 'delete-action',
  },
]

function mountMenu(meta?: string[]) {
  return mount(ActionMenu, {
    props: {
      label: 'List options',
      title: 'Groceries',
      actions,
      meta,
      triggerTestid: 'menu-trigger',
    },
  })
}

describe('ActionMenu', () => {
  describe('mobile (bottom sheet)', () => {
    beforeEach(() => stubViewport(false))

    it('renders a dialog-opening trigger with the accessible label', () => {
      const wrapper = mountMenu()
      const trigger = wrapper.get('[data-testid="menu-trigger"]')

      expect(trigger.attributes('aria-label')).toBe('List options')
      expect(trigger.attributes('aria-haspopup')).toBe('dialog')
      expect(trigger.attributes('aria-expanded')).toBe('false')
    })

    it('opens the sheet on click and emits pick when an action is chosen', async () => {
      const wrapper = mountMenu()
      await wrapper.get('[data-testid="menu-trigger"]').trigger('click')

      const sheet = wrapper.get('[data-testid="action-menu-sheet"]')
      expect(sheet.attributes('open')).toBeDefined()
      expect(sheet.text()).toContain('Groceries')

      await wrapper.get('[data-testid="delete-action"]').trigger('click')

      expect(wrapper.emitted('pick')).toEqual([['delete']])
      // Picking an action closes the sheet
      expect(sheet.attributes('open')).toBeUndefined()
    })

    it('shows meta lines in the sheet', async () => {
      const wrapper = mountMenu(['Added by Alice', 'Added Jan 1, 10:00'])
      await wrapper.get('[data-testid="menu-trigger"]').trigger('click')

      const meta = wrapper.get('[data-testid="action-menu-meta"]')
      expect(meta.text()).toContain('Added by Alice')
      expect(meta.text()).toContain('Added Jan 1, 10:00')
    })

    it('emits triggerMousedown before opening', async () => {
      const wrapper = mountMenu()
      await wrapper.get('[data-testid="menu-trigger"]').trigger('mousedown')

      expect(wrapper.emitted('triggerMousedown')).toBeTruthy()
    })
  })

  describe('desktop (dropdown)', () => {
    beforeEach(() => stubViewport(true))

    it('opens a menu and emits pick when an action is chosen', async () => {
      const wrapper = mountMenu(['Added by Alice'])
      const trigger = wrapper.get('[data-testid="menu-trigger"]')
      expect(trigger.attributes('aria-haspopup')).toBe('menu')

      await trigger.trigger('click')

      expect(wrapper.get('[data-testid="rename-action"]').text()).toBe(
        'Rename list'
      )
      expect(wrapper.get('[data-testid="action-menu-meta"]').text()).toContain(
        'Added by Alice'
      )

      await wrapper.get('[data-testid="delete-action"]').trigger('click')
      expect(wrapper.emitted('pick')).toEqual([['delete']])
    })
  })
})
