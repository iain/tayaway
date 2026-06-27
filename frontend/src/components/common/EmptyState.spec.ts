import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import { ClipboardDocumentListIcon } from '@heroicons/vue/24/outline'
import EmptyState from './EmptyState.vue'

function mountState(props: Record<string, unknown> = {}) {
  return mount(EmptyState, {
    props: {
      icon: ClipboardDocumentListIcon,
      heading: 'No chores yet',
      description: 'Add your first chore.',
      ...props,
    },
  })
}

describe('EmptyState', () => {
  it('renders the heading as an h3 by default', () => {
    const wrapper = mountState()
    expect(wrapper.find('h3').text()).toBe('No chores yet')
    expect(wrapper.find('h2').exists()).toBe(false)
  })

  it('renders an h2 when placed under a page heading', () => {
    const wrapper = mountState({ headingLevel: 2 })
    expect(wrapper.find('h2').text()).toBe('No chores yet')
    expect(wrapper.find('h3').exists()).toBe(false)
  })
})
