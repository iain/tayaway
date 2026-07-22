import { describe, it, expect, afterEach, beforeEach, vi } from 'vitest'
import { enableAutoUnmount, mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useWorkspaceStore } from '@/stores/workspace'
import { makeEvent, seedPool } from '@/test/factories'
import { useFocusedEvent } from '@/composables/useFocusedEvent'
import ChoresPage from './ChoresPage.vue'

/** ISO date `days` from today — the page reads the real clock. */
function offsetDate(days: number): string {
  return new Date(Date.now() + days * 86_400_000).toISOString().slice(0, 10)
}

const replace = vi.fn()
vi.mock('vue-router', () => ({
  useRouter: () => ({ replace }),
}))

// The redirect watcher stays live for as long as the component is mounted,
// and the pin it watches is module-level — a page left mounted by an earlier
// test would keep firing `replace` during the next one.
enableAutoUnmount(afterEach)

let pool: ReturnType<typeof useObjectPoolStore>

function mountPage() {
  return mount(ChoresPage, {
    global: {
      stubs: { AppButton: { template: '<button><slot /></button>' } },
    },
  })
}

describe('ChoresPage', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    localStorage.clear()
    replace.mockClear()
    pool = useObjectPoolStore()
    useWorkspaceStore().currentWorkspaceId = 'ws-1'
    useFocusedEvent().unpinEvent()
  })

  // /chores is a legacy entry point — it kept its own copy of the roster back
  // when the nav had a Chores item. There's one chores surface now, so the
  // URL just hands off to the focused event's tab rather than duplicating it.
  it('redirects to the focused event chores tab', () => {
    seedPool(
      pool,
      makeEvent({
        id: 'evt-now',
        name: 'Alpine Week',
        startDate: offsetDate(-1),
        endDate: offsetDate(1),
      })
    )

    mountPage()

    expect(replace).toHaveBeenCalledWith('/events/evt-now/chores')
  })

  it('follows the pin rather than the calendar', () => {
    seedPool(
      pool,
      makeEvent({
        id: 'evt-now',
        startDate: offsetDate(-1),
        endDate: offsetDate(1),
      }),
      makeEvent({
        id: 'evt-later',
        startDate: offsetDate(30),
        endDate: offsetDate(33),
      })
    )
    useFocusedEvent().pinEvent('evt-later')

    mountPage()

    expect(replace).toHaveBeenCalledWith('/events/evt-later/chores')
  })

  it('shows the empty state when no event holds focus', () => {
    const wrapper = mountPage()

    expect(replace).not.toHaveBeenCalled()
    expect(wrapper.text()).toContain('No active event')
  })
})
