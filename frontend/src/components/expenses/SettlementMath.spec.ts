import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import SettlementMath from './SettlementMath.vue'
import type { AnnotatedTransfer } from '@/utils/settlement'

function mount_(props: {
  balances: Map<string, number>
  transfers: AnnotatedTransfer[]
  nameFor: (userId: string) => string
  roundingDrift?: number
}) {
  return mount(SettlementMath, { props })
}

describe('SettlementMath', () => {
  const nameFor = (uid: string) =>
    ({ alice: 'Alice', bob: 'Bob', carol: 'Carol', dave: 'Dave' })[uid] ??
    'Unknown'

  const sampleTransfers: AnnotatedTransfer[] = [
    {
      fromUserId: 'bob',
      toUserId: 'dave',
      amount: 40,
      annotation: "Clears Bob's balance · Dave now even",
    },
    {
      fromUserId: 'carol',
      toUserId: 'alice',
      amount: 30,
      annotation: "Clears Carol's balance · Alice now even",
    },
  ]

  const sampleBalances = new Map<string, number>([
    ['alice', -30],
    ['bob', 40],
    ['carol', 30],
    ['dave', -40],
  ])

  it('renders one balance row per user with a non-zero balance', () => {
    const wrapper = mount_({
      balances: sampleBalances,
      transfers: sampleTransfers,
      nameFor,
    })
    const rows = wrapper.findAll('[data-testid="math-balance-row"]')
    expect(rows).toHaveLength(4)
  })

  it('orders creditors first (descending), then debtors (descending)', () => {
    const wrapper = mount_({
      balances: sampleBalances,
      transfers: sampleTransfers,
      nameFor,
    })
    const names = wrapper
      .findAll('[data-testid="math-balance-row"]')
      .map((r) => r.text())
    expect(names[0]).toContain('Dave')
    expect(names[0]).toContain('is owed €40.00')
    expect(names[1]).toContain('Alice')
    expect(names[1]).toContain('is owed €30.00')
    expect(names[2]).toContain('Bob')
    expect(names[2]).toContain('owes €40.00')
    expect(names[3]).toContain('Carol')
    expect(names[3]).toContain('owes €30.00')
  })

  it('renders each transfer with its annotation subtext', () => {
    const wrapper = mount_({
      balances: sampleBalances,
      transfers: sampleTransfers,
      nameFor,
    })
    const annotations = wrapper.findAll(
      '[data-testid="math-transfer-annotation"]'
    )
    expect(annotations).toHaveLength(2)
    expect(annotations[0]!.text()).toBe("Clears Bob's balance · Dave now even")
    expect(annotations[1]!.text()).toBe(
      "Clears Carol's balance · Alice now even"
    )
  })

  it('shows the rounding-drift warning when drift exceeds €0.01', () => {
    const wrapper = mount_({
      balances: sampleBalances,
      transfers: sampleTransfers,
      nameFor,
      roundingDrift: 0.05,
    })
    const drift = wrapper.find('[data-testid="math-drift"]')
    expect(drift.exists()).toBe(true)
    expect(drift.text()).toContain('€0.05')
  })

  it('hides the rounding-drift row when drift is 0 or undefined', () => {
    const wrapper = mount_({
      balances: sampleBalances,
      transfers: sampleTransfers,
      nameFor,
    })
    expect(wrapper.find('[data-testid="math-drift"]').exists()).toBe(false)
  })

  it('skips users whose rounded balance is below €0.01', () => {
    const wrapper = mount_({
      balances: new Map([
        ['alice', -0.001],
        ['bob', 0.001],
      ]),
      transfers: [],
      nameFor,
    })
    expect(wrapper.findAll('[data-testid="math-balance-row"]')).toHaveLength(0)
  })
})
