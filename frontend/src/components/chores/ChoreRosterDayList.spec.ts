import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import ChoreRosterDayList from './ChoreRosterDayList.vue'
import { makeChore, makeChoreAssignment, makeMember } from '@/test/factories'

const pad = (n: number) => String(n).padStart(2, '0')
const now = new Date()
const TODAY = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`
const NOT_TODAY = '2020-06-15'

function mountList(overrides = {}) {
  return mount(ChoreRosterDayList, {
    props: {
      chores: [
        makeChore({
          id: 'cook',
          name: 'Cooking',
          position: 1,
          peoplePerDay: 2,
          time: '18:00',
        }),
        makeChore({ id: 'wash', name: 'Washing up', position: 2 }),
      ],
      assignments: [],
      dates: [NOT_TODAY, TODAY],
      members: [makeMember({ userId: 'user-1', name: 'Alice' })],
      currentUserId: null,
      ...overrides,
    },
  })
}

describe('ChoreRosterDayList', () => {
  it('renders one section per event day', () => {
    const sections = mountList().findAll('[data-date]')
    expect(sections).toHaveLength(2)
    expect(sections.map((s) => s.attributes('data-date'))).toEqual([
      NOT_TODAY,
      TODAY,
    ])
  })

  it('lists every chore under each day', () => {
    const list = mountList()
    for (const date of [NOT_TODAY, TODAY]) {
      const section = list.get(`[data-date="${date}"]`)
      expect(section.text()).toContain('Cooking')
      expect(section.text()).toContain('Washing up')
    }
  })

  it("marks today's section and no other", () => {
    const list = mountList()
    expect(list.get(`[data-date="${TODAY}"]`).text()).toContain('Today')
    expect(list.get(`[data-date="${NOT_TODAY}"]`).text()).not.toContain('Today')
  })

  it('shows chore time and people-per-day as meta', () => {
    const row = mountList().get('[data-chore-id="cook"]')
    expect(row.text()).toContain('18:00')
    expect(row.text()).toContain('2 people')
  })

  it('places an assignment in its own day and chore slot only', () => {
    const list = mountList({
      assignments: [
        makeChoreAssignment({
          id: 'a1',
          choreId: 'cook',
          userId: 'user-1',
          date: TODAY,
        }),
      ],
    })
    const todaySlot = list.get(`[data-date="${TODAY}"] [data-chore-id="cook"]`)
    expect(todaySlot.text()).toContain('Alice')

    const otherDaySlot = list.get(
      `[data-date="${NOT_TODAY}"] [data-chore-id="cook"]`
    )
    expect(otherDaySlot.text()).not.toContain('Alice')
  })

  it('emits assign with the chore id and date of the tapped slot', async () => {
    const list = mountList()
    const slot = list.get(`[data-date="${TODAY}"] [data-chore-id="wash"]`)
    await slot.get('button[title="Assign member"]').trigger('click')

    const events = list.emitted('assign')
    expect(events).toHaveLength(1)
    expect(events![0]![0]).toBe('wash')
    expect(events![0]![1]).toBe(TODAY)
    expect(events![0]![2]).toBeInstanceOf(HTMLElement)
  })

  it('emits editAssignment when a chip is tapped', async () => {
    const assignment = makeChoreAssignment({
      id: 'a1',
      choreId: 'cook',
      userId: 'user-1',
      date: TODAY,
    })
    const list = mountList({ assignments: [assignment] })
    const chip = list
      .get(`[data-date="${TODAY}"] [data-chore-id="cook"]`)
      .get('button[aria-label="Alice"]')
    await chip.trigger('click')

    const events = list.emitted('editAssignment')
    expect(events).toHaveLength(1)
    expect((events![0]![0] as { id: string }).id).toBe('a1')
  })
})
