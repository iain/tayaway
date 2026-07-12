import { describe, it, expect, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { useObjectPoolStore } from '@/stores/objectPool'
import { makeEvent, seedPool } from '@/test/factories'
import ChoresPage from './ChoresPage.vue'

/** ISO date `days` from today — the page reads the real clock. */
function offsetDate(days: number): string {
  return new Date(Date.now() + days * 86_400_000).toISOString().slice(0, 10)
}

let pool: ReturnType<typeof useObjectPoolStore>

function mountPage() {
  return mount(ChoresPage, {
    global: {
      stubs: {
        ChoreRosterSection: {
          name: 'ChoreRosterSection',
          props: [
            'eventId',
            'title',
            'subtitle',
            'headingStyle',
            'scrollToToday',
          ],
          template: '<div class="roster-section">{{ title }}</div>',
        },
        AppButton: { template: '<button><slot /></button>' },
      },
    },
  })
}

describe('ChoresPage', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    pool = useObjectPoolStore()
  })

  it('renders a roster section for the event under way', () => {
    seedPool(
      pool,
      makeEvent({
        id: 'evt-now',
        name: 'Alpine Week',
        startDate: offsetDate(-1),
        endDate: offsetDate(1),
      })
    )

    const wrapper = mountPage()
    const sections = wrapper.findAllComponents({ name: 'ChoreRosterSection' })

    expect(sections).toHaveLength(1)
    expect(sections[0]!.props('eventId')).toBe('evt-now')
    expect(sections[0]!.props('title')).toBe('Alpine Week')
    expect(sections[0]!.props('headingStyle')).toBe('section')
    // A lone section is effectively the whole page, so it should scroll to today.
    expect(sections[0]!.props('scrollToToday')).toBe(true)
  })

  it('renders one section per overlapping event', () => {
    seedPool(
      pool,
      makeEvent({
        id: 'evt-a',
        name: 'Beach House',
        startDate: offsetDate(-2),
        endDate: offsetDate(2),
      }),
      makeEvent({
        id: 'evt-b',
        name: 'City Break',
        startDate: offsetDate(-1),
        endDate: offsetDate(3),
      })
    )

    const wrapper = mountPage()
    const sections = wrapper.findAllComponents({ name: 'ChoreRosterSection' })

    expect(sections).toHaveLength(2)
    // With multiple sections mounted, none should scroll — they'd fight over it.
    expect(sections[0]!.props('scrollToToday')).toBe(false)
    expect(sections[1]!.props('scrollToToday')).toBe(false)
  })

  it('shows the empty state when there is no active event', () => {
    const wrapper = mountPage()

    expect(
      wrapper.findAllComponents({ name: 'ChoreRosterSection' })
    ).toHaveLength(0)
    expect(wrapper.text()).toContain('No active event')
  })
})
