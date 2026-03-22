import { ref } from 'vue'
import { describe, it, expect, beforeEach } from 'vitest'
import { useActionTrigger } from './useActionTrigger'
import { useTaskActions } from './useTaskActions'
import { useDateRangeActions } from './useDateRangeActions'
import { useExpenseActions } from './useExpenseActions'

describe('useActionTrigger', () => {
  it('starts with pending false', () => {
    const { pending } = useActionTrigger()
    expect(pending.value).toBe(false)
  })

  it('sets pending to true when trigger is called', () => {
    const { pending, trigger } = useActionTrigger()
    trigger()
    expect(pending.value).toBe(true)
  })

  it('resets pending to false when reset is called', () => {
    const { pending, trigger, reset } = useActionTrigger()
    trigger()
    expect(pending.value).toBe(true)
    reset()
    expect(pending.value).toBe(false)
  })

  it('can fire a second trigger after reset', () => {
    const { pending, trigger, reset } = useActionTrigger()
    trigger()
    reset()
    trigger()
    expect(pending.value).toBe(true)
  })

  it('does not share state between separate calls', () => {
    const a = useActionTrigger()
    const b = useActionTrigger()
    a.trigger()
    expect(a.pending.value).toBe(true)
    expect(b.pending.value).toBe(false)
  })

  it('shares state when the same ref is passed in', () => {
    const shared = ref(false)
    const a = useActionTrigger(shared)
    const b = useActionTrigger(shared)
    a.trigger()
    expect(b.pending.value).toBe(true)
  })
})

describe('useTaskActions singleton', () => {
  beforeEach(() => {
    useTaskActions().resetNewList()
  })

  it('shares pendingNewList across separate calls', () => {
    const caller1 = useTaskActions()
    const caller2 = useTaskActions()
    caller1.triggerNewList()
    expect(caller2.pendingNewList.value).toBe(true)
  })

  it('reset is visible across calls', () => {
    const caller1 = useTaskActions()
    const caller2 = useTaskActions()
    caller1.triggerNewList()
    caller2.resetNewList()
    expect(caller1.pendingNewList.value).toBe(false)
  })
})

describe('useDateRangeActions singleton', () => {
  beforeEach(() => {
    useDateRangeActions().resetAdd()
  })

  it('shares pendingAdd across separate calls', () => {
    const caller1 = useDateRangeActions()
    const caller2 = useDateRangeActions()
    caller1.triggerAdd()
    expect(caller2.pendingAdd.value).toBe(true)
  })
})

describe('useExpenseActions singleton', () => {
  beforeEach(() => {
    useExpenseActions().resetAdd()
  })

  it('shares pendingAdd across separate calls', () => {
    const caller1 = useExpenseActions()
    const caller2 = useExpenseActions()
    caller1.triggerAdd()
    expect(caller2.pendingAdd.value).toBe(true)
  })
})
