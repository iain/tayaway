import { describe, it, expect } from 'vitest'
import { idempotencyKeyFor } from './commandQueue'

describe('idempotencyKeyFor', () => {
  it('produces the same key for the same set of source ids', () => {
    expect(idempotencyKeyFor(['cmd-1'])).toBe(idempotencyKeyFor(['cmd-1']))
  })

  it('produces different keys for different source id sets', () => {
    expect(idempotencyKeyFor(['cmd-1'])).not.toBe(idempotencyKeyFor(['cmd-2']))
  })

  it('is order-independent for multi-id bundles', () => {
    expect(idempotencyKeyFor(['cmd-1', 'cmd-2', 'cmd-3'])).toBe(
      idempotencyKeyFor(['cmd-3', 'cmd-1', 'cmd-2'])
    )
  })

  it('passes a single id through unchanged', () => {
    expect(idempotencyKeyFor(['cmd-1'])).toBe('cmd-1')
  })
})
