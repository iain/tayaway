import { describe, it, expect, beforeEach, vi } from 'vitest'
import { flushPromises, mount } from '@vue/test-utils'
import { ref } from 'vue'
import { createPinia, setActivePinia } from 'pinia'
import ChorePushBanner from './ChorePushBanner.vue'

const BANNER = '[data-testid="chore-push-banner"]'

const routerPush = vi.fn()
vi.mock('vue-router', () => ({
  useRouter: () => ({ push: routerPush }),
}))

const rawApiPut = vi.fn()
vi.mock('@/api/client', () => ({
  rawApi: {
    put: (...args: unknown[]) => rawApiPut(...args),
  },
}))

const push = {
  supported: ref(true),
  permission: ref<NotificationPermission | 'unsupported'>('default'),
  subscribing: ref(false),
  error: ref<string | null>(null),
  isSubscribed: vi.fn<() => Promise<boolean>>(),
  subscribe: vi.fn<() => Promise<boolean>>(),
  unsubscribe: vi.fn(),
}
vi.mock('@/composables/usePushSubscription', () => ({
  usePushSubscription: () => push,
}))

async function mountBanner() {
  const wrapper = mount(ChorePushBanner)
  await flushPromises()
  return wrapper
}

describe('ChorePushBanner', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    localStorage.clear()
    vi.clearAllMocks()
    push.supported.value = true
    push.permission.value = 'default'
    push.subscribing.value = false
    push.error.value = null
    push.isSubscribed.mockResolvedValue(false)
    push.subscribe.mockResolvedValue(true)
  })

  it('nudges to enable push notifications when this device has none', async () => {
    const wrapper = await mountBanner()

    expect(wrapper.get(BANNER).text()).toContain('push notifications')
  })

  it('stays hidden when push is already on, blocked, or unsupported', async () => {
    push.isSubscribed.mockResolvedValue(true)
    expect((await mountBanner()).find(BANNER).exists()).toBe(false)

    push.isSubscribed.mockResolvedValue(false)
    push.permission.value = 'denied'
    expect((await mountBanner()).find(BANNER).exists()).toBe(false)

    push.permission.value = 'default'
    push.supported.value = false
    expect((await mountBanner()).find(BANNER).exists()).toBe(false)
  })

  it('enables push, turns on chore push reminders, and opens notification settings', async () => {
    const wrapper = await mountBanner()

    await wrapper.get('[data-testid="chore-push-enable"]').trigger('click')
    await flushPromises()

    expect(push.subscribe).toHaveBeenCalledTimes(1)
    expect(rawApiPut).toHaveBeenCalledWith(
      '/notifications/preferences',
      { kind: 'chore_reminder', channel: 'push', enabled: true },
      { silent: true }
    )
    expect(routerPush).toHaveBeenCalledWith({ name: 'settings-notifications' })
    // The permission prompt needs the click's user gesture, so the subscribe
    // must happen before we navigate away.
    expect(push.subscribe.mock.invocationCallOrder[0]!).toBeLessThan(
      routerPush.mock.invocationCallOrder[0]!
    )
  })

  it('still opens notification settings when the subscribe is refused', async () => {
    push.subscribe.mockResolvedValue(false)
    const wrapper = await mountBanner()

    await wrapper.get('[data-testid="chore-push-enable"]').trigger('click')
    await flushPromises()

    expect(rawApiPut).not.toHaveBeenCalled()
    expect(routerPush).toHaveBeenCalledWith({ name: 'settings-notifications' })
  })

  it('"Not now" dismisses the nudge, also for future visits', async () => {
    const wrapper = await mountBanner()

    await wrapper.get('[data-testid="chore-push-dismiss"]').trigger('click')
    expect(wrapper.find(BANNER).exists()).toBe(false)

    const remounted = await mountBanner()
    expect(remounted.find(BANNER).exists()).toBe(false)
  })
})
