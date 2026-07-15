import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import EditAssignmentPopover from './EditAssignmentPopover.vue'
import {
  makeEvent,
  makeMember,
  makeAttendance,
  makeChoreAssignment,
} from '@/test/factories'
import type { PoolMember, PoolAttendance } from '@/types/pool'

const updateAssignmentSpy = vi.fn().mockResolvedValue(undefined)
const deleteAssignmentSpy = vi.fn().mockResolvedValue(undefined)

vi.mock('@/stores/choreRosters', () => ({
  useChoreRostersStore: () => ({
    updateAssignment: updateAssignmentSpy,
    deleteAssignment: deleteAssignmentSpy,
  }),
}))

const memberMap = new Map<string, PoolMember>([
  ['user-1', makeMember({ id: 'mem-1', userId: 'user-1', name: 'Alice' })],
  ['user-2', makeMember({ id: 'mem-2', userId: 'user-2', name: 'Bob' })],
  ['user-3', makeMember({ id: 'mem-3', userId: 'user-3', name: 'Cara' })],
])

describe('EditAssignmentPopover reassign', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    updateAssignmentSpy.mockClear()
  })

  const assignment = makeChoreAssignment({
    id: 'a1',
    choreId: 'chore-1',
    userId: 'user-1',
    date: '2026-03-10',
  })

  function mountPopover({
    attendances,
  }: { attendances?: PoolAttendance[] } = {}) {
    return mount(EditAssignmentPopover, {
      props: {
        assignment,
        anchorEl: document.createElement('div'),
        rosterId: 'roster-1',
        memberMap,
        assignments: [
          assignment,
          // Cara already shares this exact chore-day slot.
          makeChoreAssignment({
            id: 'a2',
            choreId: 'chore-1',
            userId: 'user-3',
            date: '2026-03-10',
          }),
        ],
        attendances: attendances ?? [
          makeAttendance({ id: 'att-user-1', userId: 'user-1' }),
          makeAttendance({ id: 'att-user-2', userId: 'user-2' }),
          makeAttendance({ id: 'att-user-3', userId: 'user-3' }),
        ],
        event: makeEvent({ startDate: '2026-03-10', endDate: '2026-03-12' }),
      },
    })
  }

  it('hands the slot to a day-attendee not already on it, then closes', async () => {
    const wrapper = mountPopover()
    await wrapper.get('button[aria-label="Reassign"]').trigger('click')

    // Not the current holder (Alice), not a slot-mate (Cara) — just Bob.
    const candidates = wrapper
      .findAll('button[aria-label^="Reassign to"]')
      .map((b) => b.attributes('aria-label'))
    expect(candidates).toEqual(['Reassign to Bob'])

    await wrapper.get('button[aria-label="Reassign to Bob"]').trigger('click')
    expect(updateAssignmentSpy).toHaveBeenCalledWith('roster-1', 'a1', {
      userId: 'user-2',
    })
    expect(wrapper.emitted('close')).toBeTruthy()
  })

  it('does not offer someone who is away that day', async () => {
    const wrapper = mountPopover({
      attendances: [
        makeAttendance({ id: 'att-user-1', userId: 'user-1' }),
        // Come-and-go: Bob is at the event, but not on this day.
        makeAttendance({
          id: 'att-2',
          userId: 'user-2',
          days: ['2026-03-11', '2026-03-12'],
        }),
        makeAttendance({ id: 'att-user-3', userId: 'user-3' }),
      ],
    })
    await wrapper.get('button[aria-label="Reassign"]').trigger('click')

    expect(wrapper.findAll('button[aria-label^="Reassign to"]')).toHaveLength(0)
    expect(wrapper.text()).toContain('No one else is around that day')
  })
})
