import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import LoginPage from '@/pages/LoginPage.vue'
import type { LoginLinkResponse } from '@/types'

const requestLoginLink = vi.fn<(email: string) => Promise<LoginLinkResponse>>()

vi.mock('vue-router', () => ({
  useRouter: () => ({ push: vi.fn() }),
  useRoute: () => ({ query: {} }),
}))

vi.mock('@/stores/auth', () => ({
  useAuthStore: () => ({
    requestLoginLink,
    authenticateWithPasskey: vi.fn(),
  }),
}))

async function submitLogin() {
  const wrapper = mount(LoginPage)
  await wrapper.find('[data-testid="email-input"]').setValue('me@example.com')
  await wrapper.find('form').trigger('submit')
  await flushPromises()
  return wrapper
}

describe('LoginPage', () => {
  beforeEach(() => {
    requestLoginLink.mockReset()
  })

  it('offers the login link directly when the response includes one (dev)', async () => {
    requestLoginLink.mockResolvedValue({
      message:
        'If an account exists with this email, a login link has been sent.',
      loginLink: 'http://localhost:5173/auth/verify?token=eyJtest',
    })

    const wrapper = await submitLogin()

    const link = wrapper.find('[data-testid="dev-login-link"]')
    expect(link.exists()).toBe(true)
    expect(link.attributes('href')).toBe(
      'http://localhost:5173/auth/verify?token=eyJtest'
    )
  })

  it('shows only the confirmation message when no link is returned', async () => {
    requestLoginLink.mockResolvedValue({
      message:
        'If an account exists with this email, a login link has been sent.',
    })

    const wrapper = await submitLogin()

    expect(wrapper.find('[data-testid="success-message"]').text()).toContain(
      'If an account exists'
    )
    expect(wrapper.find('[data-testid="dev-login-link"]').exists()).toBe(false)
  })
})
