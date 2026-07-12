import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import AssignMemberPopover from './AssignMemberPopover.vue'
import {
  makeChore,
  makeEvent,
  makeMember,
  makeRsvp,
  makeChoreAssignment,
} from '@/test/factories'
import type { PoolChore, PoolChoreAssignment, PoolRsvp } from '@/types/pool'

const createAssignmentSpy = vi
  .fn()
  .mockResolvedValue({ assignmentId: 'assign-new', queued: false })
const deleteAssignmentSpy = vi.fn().mockResolvedValue(undefined)

vi.mock('@/stores/choreRosters', () => ({
  useChoreRostersStore: () => ({
    createAssignment: createAssignmentSpy,
    deleteAssignment: deleteAssignmentSpy,
  }),
}))

describe('AssignMemberPopover', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    createAssignmentSpy.mockClear()
    deleteAssignmentSpy.mockClear()
  })

  function mountPopover({
    chore = makeChore(),
    assignments = [],
    rsvps,
    currentUserId = null,
  }: {
    chore?: PoolChore
    assignments?: PoolChoreAssignment[]
    rsvps?: PoolRsvp[]
    currentUserId?: string | null
  } = {}) {
    return mount(AssignMemberPopover, {
      props: {
        chore,
        date: '2026-03-10',
        anchorEl: document.createElement('div'),
        rosterId: 'roster-1',
        members: [
          makeMember({ id: 'mem-1', userId: 'user-1', name: 'Alice' }),
          makeMember({ id: 'mem-2', userId: 'user-2', name: 'Bob' }),
        ],
        rsvps: rsvps ?? [
          makeRsvp({ id: 'rsvp-1', userId: 'user-1' }),
          makeRsvp({ id: 'rsvp-2', userId: 'user-2' }),
        ],
        assignments,
        event: makeEvent({ startDate: '2026-03-10', endDate: '2026-03-12' }),
        currentUserId,
      },
    })
  }

  it('assigns on tap, without a note, and stays open while spots remain', async () => {
    const wrapper = mountPopover({ chore: makeChore({ peoplePerDay: 2 }) })

    expect(wrapper.find('input').exists()).toBe(false)

    await wrapper.get('button[aria-label="Assign Bob"]').trigger('click')

    expect(createAssignmentSpy).toHaveBeenCalledWith(
      'roster-1',
      'chore-1',
      'user-2',
      '2026-03-10'
    )
    expect(wrapper.emitted('close')).toBeUndefined()
  })

  it('closes after the last spot fills', async () => {
    const wrapper = mountPopover({
      chore: makeChore({ peoplePerDay: 2 }),
      assignments: [makeChoreAssignment({ userId: 'user-1' })],
    })

    await wrapper.get('button[aria-label="Assign Bob"]').trigger('click')

    expect(createAssignmentSpy).toHaveBeenCalledOnce()
    expect(wrapper.emitted('close')).toBeTruthy()
  })

  it('unassigns an already-assigned member on tap, staying open', async () => {
    const wrapper = mountPopover({
      chore: makeChore({ peoplePerDay: 2 }),
      assignments: [
        makeChoreAssignment({ id: 'assign-alice', userId: 'user-1' }),
      ],
    })

    await wrapper.get('button[aria-label="Remove Alice"]').trigger('click')

    expect(deleteAssignmentSpy).toHaveBeenCalledWith('roster-1', 'assign-alice')
    expect(createAssignmentSpy).not.toHaveBeenCalled()
    expect(wrapper.emitted('close')).toBeUndefined()
  })

  it('puts the current user first, labeled "You"', () => {
    // Alphabetically Bob comes after Alice; being the viewer moves him up.
    const wrapper = mountPopover({ currentUserId: 'user-2' })

    const labels = wrapper
      .findAll('button[aria-label^="Assign"]')
      .map((b) => b.attributes('aria-label'))
    expect(labels).toEqual(['Assign You', 'Assign Alice'])
  })

  it('does not offer members who are away on this date', () => {
    const wrapper = mountPopover({
      rsvps: [
        makeRsvp({ id: 'rsvp-1', userId: 'user-1' }),
        // Come-and-go: Bob attends the event but not this day
        makeRsvp({
          id: 'rsvp-2',
          userId: 'user-2',
          attendance: ['2026-03-11', '2026-03-12'],
        }),
      ],
    })

    expect(wrapper.find('button[aria-label="Assign Alice"]').exists()).toBe(
      true
    )
    expect(wrapper.find('button[aria-label="Assign Bob"]').exists()).toBe(false)
  })
})
