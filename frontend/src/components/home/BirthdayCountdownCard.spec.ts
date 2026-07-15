import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { mount } from '@vue/test-utils'
import BirthdayCountdownCard from './BirthdayCountdownCard.vue'
import { pickBirthdayPhrase } from '@/utils/birthdayPhrases'
import type { PoolMember } from '@/types/pool'

function makeMember(overrides: Partial<PoolMember> = {}): PoolMember {
  return {
    id: 'm1',
    objectType: 'member',
    userId: 'u1',
    workspaceId: 'w1',
    role: 'member',
    name: 'Alice Smith',
    email: 'alice@example.com',
    phoneNumber: null,
    birthday: '1990-07-15',
    locationName: null,
    latitude: null,
    longitude: null,
    updatedAt: '2024-01-01T00:00:00Z',
    ...overrides,
  } as PoolMember
}

function mountCard(member: PoolMember) {
  return mount(BirthdayCountdownCard, { props: { member } })
}

describe('BirthdayCountdownCard', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    // 2h 29m 15s before 2026-07-15 (Alice's next birthday) at local midnight.
    vi.setSystemTime(new Date('2026-07-14T21:30:45'))
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  it('renders the member and a live Luxon-formatted countdown', () => {
    const wrapper = mountCard(makeMember())

    expect(wrapper.text()).toContain('Alice Smith')
    // Under a day out → no days segment; lead hour unpadded, m/s zero-padded.
    expect(wrapper.get('.bday-countdown').text()).toBe('2h 29m 15s')

    wrapper.unmount()
  })

  it('includes a days segment for birthdays more than a day out', () => {
    // 2026-07-20 is 5 days + 2h 29m 15s out from the pinned clock.
    const wrapper = mountCard(makeMember({ birthday: '1990-07-20' }))

    expect(wrapper.get('.bday-countdown').text()).toBe('5d 02h 29m 15s')

    wrapper.unmount()
  })

  it('shows the human label and a loading percentage', () => {
    const wrapper = mountCard(makeMember())

    // Tomorrow's birthday → "Tomorrow" pill.
    expect(wrapper.text()).toContain('Tomorrow')
    // ~2.5h into a 7-day window ≈ 99% loaded.
    expect(wrapper.text()).toMatch(/9\d%/)

    wrapper.unmount()
  })

  it('ticks down every second', async () => {
    const wrapper = mountCard(makeMember())
    expect(wrapper.get('.bday-countdown').text()).toBe('2h 29m 15s')

    vi.advanceTimersByTime(1_000)
    await wrapper.vm.$nextTick()

    expect(wrapper.get('.bday-countdown').text()).toBe('2h 29m 14s')

    wrapper.unmount()
  })

  it('rotates the loading phrase onto the next time bucket', async () => {
    const wrapper = mountCard(makeMember())

    const firstBucket = Math.floor(Date.now() / 3_500)
    expect(wrapper.get('.bday-phrase').text()).toContain(
      pickBirthdayPhrase(`m1:${firstBucket}`)
    )

    // Jump well past one rotation window; the phrase follows the new bucket.
    vi.advanceTimersByTime(3_500)
    await wrapper.vm.$nextTick()

    const nextBucket = Math.floor(Date.now() / 3_500)
    expect(nextBucket).not.toBe(firstBucket)
    expect(wrapper.get('.bday-phrase').text()).toContain(
      pickBirthdayPhrase(`m1:${nextBucket}`)
    )

    wrapper.unmount()
  })

  it('renders nothing for a member without a birthday', () => {
    const wrapper = mountCard(makeMember({ birthday: null }))

    expect(wrapper.find('li').exists()).toBe(false)

    wrapper.unmount()
  })
})
