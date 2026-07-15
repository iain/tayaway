import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import { SHOW_DELAY_MS } from '@/components/common/HoverTooltip.vue'
import { createPinia, setActivePinia } from 'pinia'
import TaskItemRow from './TaskItemRow.vue'
import { useObjectPoolStore } from '@/stores/objectPool'
import { makeMember, seedPool } from '@/test/factories'
import type { PoolTaskItem } from '@/types/pool'

function mkItem(overrides: Partial<PoolTaskItem> = {}): PoolTaskItem {
  return {
    id: 'item-1',
    objectType: 'taskItem',
    taskListId: 'list-1',
    userId: 'user-1',
    content: 'Buy milk',
    completedAt: null,
    position: 1,
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    ...overrides,
  }
}

function mountRow(item: PoolTaskItem = mkItem()) {
  return mount(TaskItemRow, { props: { item } })
}

describe('TaskItemRow', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  describe('checkbox', () => {
    it('emits toggle when the checkbox changes, without entering edit mode', async () => {
      const wrapper = mountRow()
      await wrapper.get('input[type="checkbox"]').setValue(true)

      expect(wrapper.emitted('toggle')).toBeTruthy()
      expect(
        wrapper.find('[data-testid="task-item-edit-input"]').exists()
      ).toBe(false)
    })
  })

  describe('tap to edit', () => {
    it('shows the content as text (not an input) by default', () => {
      const wrapper = mountRow()
      expect(wrapper.get('[data-testid="task-item-content"]').text()).toBe(
        'Buy milk'
      )
      expect(
        wrapper.find('[data-testid="task-item-edit-input"]').exists()
      ).toBe(false)
    })

    it('swaps to an input pre-filled with the content when tapped', async () => {
      const wrapper = mountRow()
      await wrapper.get('[data-testid="task-item-content"]').trigger('click')

      const input = wrapper.get('[data-testid="task-item-edit-input"]')
      expect((input.element as HTMLInputElement).value).toBe('Buy milk')
    })

    it('emits edit with the trimmed new content on Enter', async () => {
      const wrapper = mountRow()
      await wrapper.get('[data-testid="task-item-content"]').trigger('click')

      const input = wrapper.get('[data-testid="task-item-edit-input"]')
      await input.setValue('  Buy oat milk  ')
      await input.trigger('keyup.enter')

      expect(wrapper.emitted('edit')).toBeTruthy()
      expect(wrapper.emitted('edit')![0]).toEqual([
        expect.objectContaining({ id: 'item-1' }),
        'Buy oat milk',
      ])
      // leaves edit mode
      expect(
        wrapper.find('[data-testid="task-item-edit-input"]').exists()
      ).toBe(false)
    })

    it('commits on blur', async () => {
      const wrapper = mountRow()
      await wrapper.get('[data-testid="task-item-content"]').trigger('click')

      const input = wrapper.get('[data-testid="task-item-edit-input"]')
      await input.setValue('Buy oat milk')
      await input.trigger('blur')

      expect(wrapper.emitted('edit')![0]).toEqual([
        expect.objectContaining({ id: 'item-1' }),
        'Buy oat milk',
      ])
    })

    it('does not emit edit when the content is unchanged', async () => {
      const wrapper = mountRow()
      await wrapper.get('[data-testid="task-item-content"]').trigger('click')

      const input = wrapper.get('[data-testid="task-item-edit-input"]')
      await input.trigger('keyup.enter')

      expect(wrapper.emitted('edit')).toBeFalsy()
    })

    it('does not emit edit when the value only differs by surrounding whitespace', async () => {
      // Stored content has leading/trailing space; opening and closing the
      // editor without real changes must not fire a no-op rewrite.
      const wrapper = mountRow(mkItem({ content: '  Buy milk  ' }))
      await wrapper.get('[data-testid="task-item-content"]').trigger('click')

      const input = wrapper.get('[data-testid="task-item-edit-input"]')
      await input.trigger('keyup.enter')

      expect(wrapper.emitted('edit')).toBeFalsy()
    })

    it('cancels the edit instead of committing when the item menu opens mid-edit', async () => {
      const wrapper = mountRow()
      await wrapper.get('[data-testid="task-item-content"]').trigger('click')

      const input = wrapper.get('[data-testid="task-item-edit-input"]')
      await input.setValue('Buy oat milk')

      // Opening the menu cancels the edit before the input's blur can commit,
      // so no spurious content update races the action picked from the menu.
      const menuTrigger = wrapper.get('[data-testid="item-menu-button"]')
      await menuTrigger.trigger('mousedown')
      await input.trigger('blur')
      await menuTrigger.trigger('click')
      await wrapper.get('[data-testid="delete-item-button"]').trigger('click')

      expect(wrapper.emitted('edit')).toBeFalsy()
      expect(wrapper.emitted('delete')).toBeTruthy()
    })

    it('does not emit edit when cleared to empty', async () => {
      const wrapper = mountRow()
      await wrapper.get('[data-testid="task-item-content"]').trigger('click')

      const input = wrapper.get('[data-testid="task-item-edit-input"]')
      await input.setValue('   ')
      await input.trigger('keyup.enter')

      expect(wrapper.emitted('edit')).toBeFalsy()
    })

    it('cancels on Escape without emitting', async () => {
      const wrapper = mountRow()
      await wrapper.get('[data-testid="task-item-content"]').trigger('click')

      const input = wrapper.get('[data-testid="task-item-edit-input"]')
      await input.setValue('changed')
      await input.trigger('keyup.escape')

      expect(wrapper.emitted('edit')).toBeFalsy()
      expect(
        wrapper.find('[data-testid="task-item-edit-input"]').exists()
      ).toBe(false)
      // original text restored
      expect(wrapper.get('[data-testid="task-item-content"]').text()).toBe(
        'Buy milk'
      )
    })
  })

  describe('item menu', () => {
    it('emits delete when Delete item is picked from the menu', async () => {
      const wrapper = mountRow()
      await wrapper.get('[data-testid="item-menu-button"]').trigger('click')
      await wrapper.get('[data-testid="delete-item-button"]').trigger('click')

      expect(wrapper.emitted('delete')).toBeTruthy()
      expect(wrapper.emitted('delete')![0]).toEqual([
        expect.objectContaining({ id: 'item-1' }),
      ])
    })

    it('shows who added the item and when', async () => {
      seedPool(
        useObjectPoolStore(),
        makeMember({ userId: 'user-1', name: 'Alice' })
      )
      const wrapper = mountRow(
        mkItem({ createdAt: '2026-07-10T09:30:00.000Z' })
      )
      await wrapper.get('[data-testid="item-menu-button"]').trigger('click')

      const meta = wrapper.get('[data-testid="action-menu-meta"]').text()
      expect(meta).toContain('Added by Alice')
      expect(meta).toMatch(/Added .*Jul/)
      expect(meta).not.toContain('Completed')
    })

    it('adds the completion moment for completed items', async () => {
      const wrapper = mountRow(
        mkItem({ completedAt: '2026-07-11T14:05:00.000Z' })
      )
      await wrapper.get('[data-testid="item-menu-button"]').trigger('click')

      const meta = wrapper.get('[data-testid="action-menu-meta"]').text()
      expect(meta).toContain('Added by Unknown')
      expect(meta).toMatch(/Completed .*Jul/)
    })
  })

  describe('metadata hover tooltip', () => {
    beforeEach(() => {
      vi.useFakeTimers()
      vi.stubGlobal(
        'matchMedia',
        vi.fn().mockImplementation((query: string) => ({
          matches: query === '(hover: hover)',
          media: query,
          onchange: null,
          addListener: vi.fn(),
          removeListener: vi.fn(),
          addEventListener: vi.fn(),
          removeEventListener: vi.fn(),
          dispatchEvent: vi.fn(),
        }))
      )
    })

    afterEach(() => {
      vi.useRealTimers()
      vi.unstubAllGlobals()
    })

    async function hoverRow(wrapper: ReturnType<typeof mountRow>) {
      // The tooltip mounts once the row's template ref resolves, a tick after
      // the row itself.
      await wrapper.vm.$nextTick()
      wrapper
        .get('[data-testid="task-item-row"]')
        .element.dispatchEvent(new MouseEvent('mouseenter'))
      vi.advanceTimersByTime(SHOW_DELAY_MS)
      await wrapper.vm.$nextTick()
      return document.body.querySelector('[role="tooltip"]')
    }

    it('shows who added the item and when on row hover', async () => {
      seedPool(
        useObjectPoolStore(),
        makeMember({ userId: 'user-1', name: 'Alice' })
      )
      const wrapper = mountRow(
        mkItem({ createdAt: '2026-07-10T09:30:00.000Z' })
      )

      const tooltip = await hoverRow(wrapper)
      expect(tooltip).not.toBeNull()
      expect(tooltip!.textContent).toContain('Added by Alice')
      expect(tooltip!.textContent).toMatch(/Added .*Jul/)
      expect(tooltip!.textContent).not.toContain('Completed')
      wrapper.unmount()
    })

    it('includes the completion moment for completed items', async () => {
      const wrapper = mountRow(
        mkItem({ completedAt: '2026-07-11T14:05:00.000Z' })
      )

      const tooltip = await hoverRow(wrapper)
      expect(tooltip!.textContent).toMatch(/Completed .*Jul/)
      wrapper.unmount()
    })
  })

  describe('history rows', () => {
    it('hides the drag handle when inHistory is set', () => {
      const wrapper = mount(TaskItemRow, {
        props: { item: mkItem(), inHistory: true },
      })
      expect(
        wrapper.find('[data-testid="task-item-drag-handle"]').exists()
      ).toBe(false)
    })
  })
})
