import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import ChoreSummaryTable from './ChoreSummaryTable.vue'
import {
  makeChore,
  makeEvent,
  makeMember,
  makeRsvp,
  makeChoreAssignment,
} from '@/test/factories'

function mountTable() {
  return mount(ChoreSummaryTable, {
    props: {
      chores: [makeChore({ id: 'cook', name: 'Cooking' })],
      assignments: [
        makeChoreAssignment({
          id: 'a1',
          choreId: 'cook',
          userId: 'user-1',
          date: '2026-03-10',
        }),
        makeChoreAssignment({
          id: 'a2',
          choreId: 'cook',
          userId: 'user-2',
          date: '2026-03-11',
        }),
        makeChoreAssignment({
          id: 'a3',
          choreId: 'cook',
          userId: 'user-2',
          date: '2026-03-12',
        }),
      ],
      members: [
        makeMember({ id: 'mem-1', userId: 'user-1', name: 'Alice' }),
        makeMember({ id: 'mem-2', userId: 'user-2', name: 'Bob' }),
      ],
      rsvps: [
        // Alice is only around one day; Bob stays the whole event.
        makeRsvp({ id: 'r1', userId: 'user-1', attendance: ['2026-03-10'] }),
        makeRsvp({ id: 'r2', userId: 'user-2' }),
      ],
      event: makeEvent({ startDate: '2026-03-10', endDate: '2026-03-12' }),
    },
  })
}

describe('ChoreSummaryTable', () => {
  it('orders rows by load, heaviest first', () => {
    const names = mountTable()
      .findAll('tbody th')
      .map((cell) => cell.text())
    expect(names).toEqual(['Bob', 'Alice'])
  })

  it('shows how many days each person is there, so uneven totals read as fair', () => {
    const rows = mountTable().findAll('tbody tr')
    const daysThere = rows.map((row) => row.findAll('td').at(-1)!.text())
    expect(daysThere).toEqual(['3', '1']) // Bob all 3 days, Alice just 1
  })
})
