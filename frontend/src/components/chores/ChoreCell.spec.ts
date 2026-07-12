import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import ChoreCell from './ChoreCell.vue'
import { makeMember, makeChoreAssignment } from '@/test/factories'
import type { PoolMember } from '@/types/pool'

const memberMap = new Map<string, PoolMember>([
  ['user-1', makeMember({ userId: 'user-1', name: 'Alice' })],
])

function mountCell(
  assignment: Partial<ReturnType<typeof makeChoreAssignment>>,
  currentUserId: string | null = null,
  staleAssignmentIds?: Set<string>
) {
  return mount(ChoreCell, {
    props: {
      assignments: [makeChoreAssignment({ userId: 'user-1', ...assignment })],
      peoplePerDay: 1,
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
})
