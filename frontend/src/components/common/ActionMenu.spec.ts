import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { mount } from '@vue/test-utils'
import ActionMenu from './ActionMenu.vue'
import type { ActionMenuAction } from './ActionMenu.vue'

// The global setup stubs matchMedia to always-false, so specs run against
// the mobile bottom sheet by default; the desktop block stubs `matches: true`
// to exercise the dropdown branch.
const realMatchMedia = window.matchMedia

function stubDesktopViewport(): void {
  window.matchMedia = vi.fn().mockImplementation((query: string) => ({
    ...realMatchMedia(query),
    matches: true,
  })) as unknown as typeof window.matchMedia
}

const onRename = vi.fn()
const onDelete = vi.fn()

const actions: ActionMenuAction[] = [
  { label: 'Rename list', testid: 'rename-action', onPick: onRename },
  {
    label: 'Delete list',
    danger: true,
    testid: 'delete-action',
    onPick: onDelete,
  },
]

function mountMenu(meta?: string[] | (() => string[])) {
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

beforeEach(() => {
  onRename.mockClear()
  onDelete.mockClear()
})

describe('ActionMenu', () => {
  describe('mobile (bottom sheet)', () => {
    it('renders a dialog-opening trigger with the accessible label', () => {
      const wrapper = mountMenu()
      const trigger = wrapper.get('[data-testid="menu-trigger"]')

      expect(trigger.attributes('aria-label')).toBe('List options')
      expect(trigger.attributes('aria-haspopup')).toBe('dialog')
      expect(trigger.attributes('aria-expanded')).toBe('false')
    })

    it('defers rendering the sheet body until first opened', async () => {
      const wrapper = mountMenu()
      expect(wrapper.find('[data-testid="delete-action"]').exists()).toBe(false)

      await wrapper.get('[data-testid="menu-trigger"]').trigger('click')
      expect(wrapper.find('[data-testid="delete-action"]').exists()).toBe(true)
    })

    it('opens the sheet on click and runs the picked action', async () => {
      const wrapper = mountMenu()
      await wrapper.get('[data-testid="menu-trigger"]').trigger('click')

      const sheet = wrapper.get('[data-testid="action-menu-sheet"]')
      expect(sheet.attributes('open')).toBeDefined()
      expect(sheet.text()).toContain('Groceries')

      await wrapper.get('[data-testid="delete-action"]').trigger('click')

      expect(onDelete).toHaveBeenCalledOnce()
      // Picking an action closes the sheet
      expect(sheet.attributes('open')).toBeUndefined()
    })

    it('shows meta lines in the sheet, resolving getter-shaped meta', async () => {
      const meta = vi.fn(() => ['Added by Alice', 'Added Jan 1, 10:00'])
      const wrapper = mountMenu(meta)
      await wrapper.get('[data-testid="menu-trigger"]').trigger('click')

      const block = wrapper.get('[data-testid="action-menu-meta"]')
      expect(block.text()).toContain('Added by Alice')
      expect(block.text()).toContain('Added Jan 1, 10:00')
    })

    it('emits triggerMousedown before opening', async () => {
      const wrapper = mountMenu()
      await wrapper.get('[data-testid="menu-trigger"]').trigger('mousedown')

      expect(wrapper.emitted('triggerMousedown')).toBeTruthy()
    })
  })

  describe('desktop (dropdown)', () => {
    beforeEach(() => stubDesktopViewport())
    afterEach(() => {
      window.matchMedia = realMatchMedia
    })

    it('opens a menu and runs the picked action', async () => {
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
      expect(onDelete).toHaveBeenCalledOnce()
    })
  })
})
