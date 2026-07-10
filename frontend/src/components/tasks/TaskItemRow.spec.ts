import { describe, it, expect, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import TaskItemRow from './TaskItemRow.vue'
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

    it('cancels the edit instead of committing when Delete is pressed mid-edit', async () => {
      const wrapper = mountRow()
      await wrapper.get('[data-testid="task-item-content"]').trigger('click')

      const input = wrapper.get('[data-testid="task-item-edit-input"]')
      await input.setValue('Buy oat milk')

      // Pressing delete cancels the edit before the input's blur can commit,
      // so no spurious content update races the deletion.
      const deleteButton = wrapper.get('button')
      await deleteButton.trigger('mousedown')
      await input.trigger('blur')
      await deleteButton.trigger('click')

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
})
