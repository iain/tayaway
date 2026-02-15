import { describe, it, expect, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import HomePage from '@/pages/HomePage.vue'

vi.mock('vue-router', () => ({
  useRouter: () => ({
    push: vi.fn(),
  }),
}))

describe('HomePage', () => {
  it('renders the dashboard title', () => {
    setActivePinia(createPinia())
    const wrapper = mount(HomePage)
    expect(wrapper.text()).toContain('Dashboard')
  })
})
