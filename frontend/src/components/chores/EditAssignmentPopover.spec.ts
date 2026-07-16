import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import EditAssignmentPopover from './EditAssignmentPopover.vue'
import {
  makeEvent,
  makeMember,
  makeHydratedAttendance,
  makeChoreAssignment,
} from '@/test/factories'
import type { PoolMember } from '@/types/pool'
import type { HydratedAttendance } from '@/composables/useHydratedEvent'

const updateAssignmentSpy = vi.fn().mockResolvedValue(undefined)
const deleteAssignmentSpy = vi.fn().mockResolvedValue(undefined)

vi.mock('@/stores/choreRosters', () => ({
  useChoreRostersStore: () => ({
    updateAssignment: updateAssignmentSpy,
    deleteAssignment: deleteAssignmentSpy,
  }),
}))

const alice = makeMember({ id: 'mem-1', userId: 'user-1', name: 'Alice' })
const bob = makeMember({ id: 'mem-2', userId: 'user-2', name: 'Bob' })
const cara = makeMember({ id: 'mem-3', userId: 'user-3', name: 'Cara' })

const memberMap = new Map<string, PoolMember>([
  ['user-1', alice],
  ['user-2', bob],
  ['user-3', cara],
])

function att(
  id: string,
  member: PoolMember,
  overrides: { days?: string[] } = {}
): HydratedAttendance {
  return makeHydratedAttendance(
    { id, userId: member.userId, ...overrides },
    { member }
  )
}

describe('EditAssignmentPopover reassign', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    updateAssignmentSpy.mockClear()
  })

  const assignment = makeChoreAssignment({
    id: 'a1',
    choreId: 'chore-1',
    attendanceId: 'att-user-1',
    userId: 'user-1',
    date: '2026-03-10',
  })

  function mountPopover({
    attendances,
  }: { attendances?: HydratedAttendance[] } = {}) {
    const resolved = attendances ?? [
      att('att-user-1', alice),
      att('att-user-2', bob),
      att('att-user-3', cara),
    ]
    return mount(EditAssignmentPopover, {
      props: {
        assignment,
        anchorEl: document.createElement('div'),
        rosterId: 'roster-1',
        attendanceMap: new Map(resolved.map((a) => [a.id, a])),
        memberMap,
        assignments: [
          assignment,
          // Cara already shares this exact chore-day slot.
          makeChoreAssignment({
            id: 'a2',
            choreId: 'chore-1',
            attendanceId: 'att-user-3',
            userId: 'user-3',
            date: '2026-03-10',
          }),
        ],
        attendances: resolved,
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
      attendanceId: 'att-user-2',
      userId: 'user-2',
    })
    expect(wrapper.emitted('close')).toBeTruthy()
  })

  it('does not offer someone who is away that day', async () => {
    const wrapper = mountPopover({
      attendances: [
        att('att-user-1', alice),
        // Come-and-go: Bob is at the event, but not on this day.
        att('att-2', bob, { days: ['2026-03-11', '2026-03-12'] }),
        att('att-user-3', cara),
      ],
    })
    await wrapper.get('button[aria-label="Reassign"]').trigger('click')

    expect(wrapper.findAll('button[aria-label^="Reassign to"]')).toHaveLength(0)
    expect(wrapper.text()).toContain('No one else is around that day')
  })

  it('excludes a legacy slot-mate row without an attendance link', async () => {
    const wrapper = mount(EditAssignmentPopover, {
      props: {
        assignment,
        anchorEl: document.createElement('div'),
        rosterId: 'roster-1',
        attendanceMap: new Map(
          [att('att-user-1', alice), att('att-user-2', bob)].map((a) => [
            a.id,
            a,
          ])
        ),
        memberMap,
        assignments: [
          assignment,
          // Bob shares the slot through a legacy row: no attendanceId.
          makeChoreAssignment({
            id: 'a2',
            choreId: 'chore-1',
            attendanceId: null,
            userId: 'user-2',
            date: '2026-03-10',
          }),
        ],
        attendances: [att('att-user-1', alice), att('att-user-2', bob)],
        event: makeEvent({ startDate: '2026-03-10', endDate: '2026-03-12' }),
      },
    })
    await wrapper.get('button[aria-label="Reassign"]').trigger('click')

    expect(wrapper.findAll('button[aria-label^="Reassign to"]')).toHaveLength(0)
  })
})
