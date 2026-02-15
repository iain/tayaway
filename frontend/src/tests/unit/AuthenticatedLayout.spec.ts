import { describe, it, expect, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import AuthenticatedLayout from '@/layouts/AuthenticatedLayout.vue'

// Mock vue-router
vi.mock('vue-router', () => ({
  useRouter: () => ({
    push: vi.fn(),
  }),
  useRoute: () => ({
    name: 'home',
  }),
}))

describe('AuthenticatedLayout', () => {
  it('mounts without template syntax errors', () => {
    setActivePinia(createPinia())

    const wrapper = mount(AuthenticatedLayout, {
      shallow: true,
      global: {
        stubs: {
          'router-link': true,
          RouterView: true,
          Disclosure: true,
          DisclosureButton: true,
          DisclosurePanel: true,
          Menu: true,
          MenuButton: true,
          MenuItem: true,
          MenuItems: true,
        },
      },
    })

    expect(wrapper.exists()).toBe(true)
  })
})
