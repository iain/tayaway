import { describe, it, expect } from 'vitest'
import { mount, type VueWrapper } from '@vue/test-utils'
import VoteBreakdown from './VoteBreakdown.vue'
import { makeMember } from '@/test/factories'
import type { HydratedVote } from '@/composables/useHydratedEvent'
import type { VoteResponse } from '@/types/pool'

function member(userId: string, name: string | null, email?: string) {
  return makeMember({
    id: `member-${userId}`,
    userId,
    name,
    email: email ?? `${userId}@example.com`,
  })
}

function makeVote(
  userId: string,
  response: VoteResponse,
  overrides: { name?: string | null; comment?: string | null } = {}
): HydratedVote {
  return {
    id: `vote-${userId}`,
    objectType: 'vote',
    dateRangeId: 'dr-1',
    userId,
    member: member(userId, overrides.name ?? userId),
    response,
    comment: overrides.comment ?? null,
    updatedAt: '2026-01-01T00:00:00.000Z',
    createdAt: '2026-01-01T00:00:00.000Z',
  }
}

function readGroups(wrapper: VueWrapper) {
  return wrapper
    .findAll('[data-testid="vote-breakdown-group"]')
    .map((group) => ({
      label: group.get('[data-testid="vote-breakdown-label"]').text(),
      names: group.get('[data-testid="vote-breakdown-names"]').text(),
    }))
}

describe('VoteBreakdown', () => {
  it('lists voters grouped by response, best answer first', () => {
    const wrapper = mount(VoteBreakdown, {
      props: {
        votes: [
          makeVote('u1', 'no', { name: 'Bram Jansen' }),
          makeVote('u2', 'yes', { name: 'Sanne de Wit' }),
          makeVote('u3', 'preferably_not', { name: 'Fenna de Vries' }),
          makeVote('u4', 'yes', { name: 'Merel Bakker' }),
        ],
        members: [],
      },
    })

    expect(readGroups(wrapper)).toEqual([
      { label: 'Yes', names: 'Sanne de Wit, Merel Bakker' },
      { label: 'Preferably not', names: 'Fenna de Vries' },
      { label: 'No', names: 'Bram Jansen' },
    ])
    expect(
      wrapper.find('[data-testid="vote-breakdown-comments-toggle"]').exists()
    ).toBe(false)
  })

  it('renders nothing until someone votes on the option', () => {
    const wrapper = mount(VoteBreakdown, {
      props: { votes: [], members: [member('u1', 'Sanne de Wit')] },
    })

    expect(wrapper.text()).toBe('')
  })

  it('closes with the members who have not voted on this option', () => {
    const wrapper = mount(VoteBreakdown, {
      props: {
        votes: [makeVote('u1', 'yes', { name: 'Sanne de Wit' })],
        members: [
          member('u1', 'Sanne de Wit'),
          member('u2', 'Lotte Peters'),
          member('u3', null, 'tom@example.com'),
        ],
      },
    })

    expect(readGroups(wrapper)).toEqual([
      { label: 'Yes', names: 'Sanne de Wit' },
      { label: 'Not voted', names: 'Lotte Peters, tom@example.com' },
    ])
  })

  it('keeps vote comments behind a toggle', async () => {
    const wrapper = mount(VoteBreakdown, {
      props: {
        votes: [
          makeVote('u1', 'yes', { name: 'Sanne de Wit' }),
          makeVote('u2', 'no', {
            name: 'Joris Klein',
            comment: 'Wedding that weekend',
          }),
        ],
        members: [],
      },
    })

    expect(wrapper.text()).not.toContain('Wedding that weekend')

    const toggle = wrapper.get('[data-testid="vote-breakdown-comments-toggle"]')
    expect(toggle.text()).toContain('1 comment')

    await toggle.trigger('click')
    expect(
      wrapper.get('[data-testid="vote-breakdown-comment"]').text()
    ).toContain('Wedding that weekend')
  })
})
