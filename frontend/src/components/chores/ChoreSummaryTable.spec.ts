import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import ChoreSummaryTable from './ChoreSummaryTable.vue'
import {
  makeChore,
  makeEvent,
  makeGuest,
  makeHydratedAttendance,
  makeMember,
  makeChoreAssignment,
} from '@/test/factories'

const alice = makeMember({ id: 'mem-1', userId: 'user-1', name: 'Alice' })
const bob = makeMember({ id: 'mem-2', userId: 'user-2', name: 'Bob' })
const carol = makeMember({ id: 'mem-3', userId: 'user-3', name: 'Carol' })

function mountTable(headingLevel?: 2 | 3) {
  return mount(ChoreSummaryTable, {
    props: {
      chores: [makeChore({ id: 'cook', name: 'Cooking' })],
      assignments: [
        makeChoreAssignment({
          id: 'a1',
          choreId: 'cook',
          attendanceId: 'att-1',
          userId: 'user-1',
          date: '2026-03-10',
        }),
        makeChoreAssignment({
          id: 'a2',
          choreId: 'cook',
          attendanceId: 'att-user-2',
          userId: 'user-2',
          date: '2026-03-11',
        }),
        // A legacy row without the attendance link still counts toward Bob.
        makeChoreAssignment({
          id: 'a3',
          choreId: 'cook',
          attendanceId: null,
          userId: 'user-2',
          date: '2026-03-12',
        }),
      ],
      members: [alice, bob, carol],
      attendances: [
        // Alice is only around one day; Bob stays the whole event; Carol is
        // there for two days but holds no chores at all.
        makeHydratedAttendance(
          { id: 'att-1', userId: 'user-1', days: ['2026-03-10'] },
          { member: alice }
        ),
        makeHydratedAttendance(
          { id: 'att-user-2', userId: 'user-2' },
          { member: bob }
        ),
        makeHydratedAttendance(
          { id: 'att-3', userId: 'user-3', days: ['2026-03-11', '2026-03-12'] },
          { member: carol }
        ),
      ],
      event: makeEvent({ startDate: '2026-03-10', endDate: '2026-03-12' }),
      ...(headingLevel !== undefined ? { headingLevel } : {}),
    },
  })
}

describe('ChoreSummaryTable', () => {
  it('orders rows by load, heaviest first, including chore-less attendees', () => {
    const names = mountTable()
      .findAll('tbody th')
      .map((cell) => cell.text())
    expect(names).toEqual(['Bob', 'Alice', 'Carol'])
  })

  it('shows how many days each person is there, so uneven totals read as fair', () => {
    const rows = mountTable().findAll('tbody tr')
    const daysThere = rows.map((row) => row.findAll('td').at(-2)!.text())
    expect(daysThere).toEqual(['3', '1', '2'])
  })

  it('shows each person’s chores per day there — the rate auto-fill balances on', () => {
    const rows = mountTable().findAll('tbody tr')
    const perDay = rows.map((row) => row.findAll('td').at(-1)!.text())
    // Bob 2 chores / 3 days, Alice 1/1, Carol 0/2.
    expect(perDay).toEqual(['0.7', '1.0', '0.0'])
  })

  it('gives a going guest their own row', () => {
    const wrapper = mount(ChoreSummaryTable, {
      props: {
        chores: [makeChore({ id: 'cook', name: 'Cooking' })],
        assignments: [
          makeChoreAssignment({
            id: 'a1',
            choreId: 'cook',
            attendanceId: 'att-g',
            userId: null,
            date: '2026-03-10',
          }),
        ],
        members: [alice],
        attendances: [
          makeHydratedAttendance(
            { id: 'att-1', userId: 'user-1' },
            { member: alice }
          ),
          makeHydratedAttendance(
            {
              id: 'att-g',
              userId: null,
              guestId: 'guest-1',
              hostUserId: 'user-1',
            },
            { guest: makeGuest({ id: 'guest-1', name: 'Emma' }) }
          ),
        ],
        event: makeEvent({ startDate: '2026-03-10', endDate: '2026-03-12' }),
      },
    })

    const names = wrapper.findAll('tbody th').map((cell) => cell.text())
    expect(names).toEqual(['Emma', 'Alice'])
  })

  it('renders the Workload heading as an h2 by default', () => {
    const wrapper = mountTable()
    const h2 = wrapper.get('h2')
    expect(h2.text()).toBe('Workload')
    expect(wrapper.find('h3').exists()).toBe(false)
  })

  it('demotes the Workload heading to h3 when nested under a section', () => {
    const wrapper = mountTable(3)
    const h3 = wrapper.get('h3')
    expect(h3.text()).toBe('Workload')
    expect(wrapper.find('h2').exists()).toBe(false)
  })
})
