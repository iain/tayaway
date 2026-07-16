import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import ChoreCell from './ChoreCell.vue'
import {
  makeGuest,
  makeHydratedAttendance,
  makeMember,
  makeChoreAssignment,
} from '@/test/factories'
import type { PoolMember } from '@/types/pool'
import type { HydratedAttendance } from '@/composables/useHydratedEvent'

const memberMap = new Map<string, PoolMember>([
  ['user-1', makeMember({ userId: 'user-1', name: 'Alice' })],
])

const attendanceMap = new Map<string, HydratedAttendance>([
  [
    'att-1',
    makeHydratedAttendance(
      { id: 'att-1', userId: 'user-1' },
      { member: makeMember({ userId: 'user-1', name: 'Alice' }) }
    ),
  ],
  [
    'att-g',
    makeHydratedAttendance(
      { id: 'att-g', userId: null, guestId: 'guest-1', hostUserId: 'user-1' },
      { guest: makeGuest({ id: 'guest-1', name: 'Emma' }) }
    ),
  ],
])

function mountCell(
  assignment: Partial<ReturnType<typeof makeChoreAssignment>>,
  currentUserId: string | null = null,
  staleAssignmentIds?: Set<string>
) {
  return mount(ChoreCell, {
    props: {
      assignments: [
        makeChoreAssignment({
          attendanceId: 'att-1',
          userId: 'user-1',
          ...assignment,
        }),
      ],
      peoplePerDay: 1,
      attendanceMap,
      memberMap,
      currentUserId,
      staleAssignmentIds,
    },
  })
}

describe('ChoreCell assignment chip', () => {
  it('names the chip after the member for screen readers', () => {
    const chip = mountCell({ pinned: false, note: null }).get('button')
    expect(chip.attributes('aria-label')).toBe('Alice')
  })

  it('folds pinned state and note text into the accessible name', () => {
    const chip = mountCell({ pinned: true, note: 'deep clean' }).get('button')
    expect(chip.attributes('aria-label')).toBe(
      'Alice, pinned, note: deep clean'
    )
  })

  it('keeps the note in the title for the hover tooltip', () => {
    const chip = mountCell({ note: 'deep clean' }).get('button')
    expect(chip.attributes('title')).toContain('deep clean')
  })

  it("folds 'you' into the accessible name for the current user's own chip", () => {
    const chip = mountCell({}, 'user-1').get('button')
    expect(chip.attributes('aria-label')).toBe('Alice, you')
  })

  it("does not mark someone else's chip as the current user", () => {
    const chip = mountCell({}, 'user-2').get('button')
    expect(chip.attributes('aria-label')).toBe('Alice')
  })

  it('marks a stale assignment in the accessible name and tooltip', () => {
    const chip = mountCell({ id: 'a1' }, null, new Set(['a1'])).get('button')
    expect(chip.attributes('aria-label')).toBe('Alice, not attending this day')
    expect(chip.attributes('title')).toContain('not attending this day')
  })

  it('leaves chips alone when the stale set names another assignment', () => {
    const chip = mountCell({ id: 'a1' }, null, new Set(['other'])).get('button')
    expect(chip.attributes('aria-label')).toBe('Alice')
  })

  it("names a guest holder's chip after the guest", () => {
    const chip = mountCell({ attendanceId: 'att-g', userId: null }).get(
      'button'
    )
    expect(chip.attributes('aria-label')).toBe('Emma')
  })

  it('falls back to the mirrored userId on a legacy row without a link', () => {
    const chip = mountCell({ attendanceId: null, userId: 'user-1' }).get(
      'button'
    )
    expect(chip.attributes('aria-label')).toBe('Alice')
  })
})
