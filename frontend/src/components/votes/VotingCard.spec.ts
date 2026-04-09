import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import VotingCard from './VotingCard.vue'
import type { HydratedDateRange } from '@/composables/useHydratedEvent'

const submitVote = vi.fn().mockResolvedValue(undefined)

vi.mock('@/stores/votes', () => ({
  useVotesStore: () => ({
    submitVote,
  }),
}))

function makeDateRange(
  overrides: Partial<HydratedDateRange> = {}
): HydratedDateRange {
  return {
    id: 'dr-1',
    datePollId: 'poll-1',
    startDate: '2026-06-01',
    endDate: '2026-06-03',
    votes: [],
    voteSummary: { yes: 0, no: 0, preferably_not: 0, total: 0 },
    ...overrides,
  }
}

describe('VotingCard', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    submitVote.mockClear()
  })

  it('passes the comment input value when changing vote response', async () => {
    const dateRange = makeDateRange({
      votes: [
        {
          id: 'vote-1',
          dateRangeId: 'dr-1',
          userId: 'user-1',
          member: undefined,
          response: 'yes' as const,
          comment: 'Old comment',
          updatedAt: '2026-01-01T00:00:00.000Z',
          createdAt: '2026-01-01T00:00:00.000Z',
        },
      ],
    })

    const wrapper = mount(VotingCard, {
      props: { dateRange, eventId: 'evt-1', currentUserId: 'user-1' },
    })

    // The comment input should be initialized with the existing comment
    const textarea = wrapper.find('textarea')
    expect(textarea.exists()).toBe(true)
    expect((textarea.element as HTMLTextAreaElement).value).toBe('Old comment')

    // User types a new comment
    await textarea.setValue('New comment')

    // User clicks a different vote response
    const noButton = wrapper.findAll('button').find((b) => b.text() === 'No')
    await noButton!.trigger('click')

    // submitVote should receive the NEW comment, not the old one
    expect(submitVote).toHaveBeenCalledWith(
      'evt-1',
      'dr-1',
      'no',
      'New comment'
    )
  })

  it('passes undefined when comment input is empty', async () => {
    const dateRange = makeDateRange({
      votes: [
        {
          id: 'vote-1',
          dateRangeId: 'dr-1',
          userId: 'user-1',
          member: undefined,
          response: 'yes' as const,
          comment: 'Old comment',
          updatedAt: '2026-01-01T00:00:00.000Z',
          createdAt: '2026-01-01T00:00:00.000Z',
        },
      ],
    })

    const wrapper = mount(VotingCard, {
      props: { dateRange, eventId: 'evt-1', currentUserId: 'user-1' },
    })

    // Clear the comment
    await wrapper.find('textarea').setValue('')

    // Change vote
    const noButton = wrapper.findAll('button').find((b) => b.text() === 'No')
    await noButton!.trigger('click')

    expect(submitVote).toHaveBeenCalledWith('evt-1', 'dr-1', 'no', undefined)
  })
})
