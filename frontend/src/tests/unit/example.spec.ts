import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import HomePage from '@/pages/HomePage.vue'

describe('HomePage', () => {
  it('renders the title', () => {
    const wrapper = mount(HomePage)
    expect(wrapper.text()).toContain('Tayaway')
  })
})
