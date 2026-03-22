import { describe, it, expect } from 'vitest'
import { useActionTrigger } from './useActionTrigger'

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
})
