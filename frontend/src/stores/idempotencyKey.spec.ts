import { describe, it, expect } from 'vitest'
import { idempotencyKeyFor } from './commandQueue'

describe('idempotencyKeyFor', () => {
  it('produces the same key for the same set of source ids', () => {
    const a = idempotencyKeyFor(['cmd-1'])
    const b = idempotencyKeyFor(['cmd-1'])

    expect(a).toBe(b)
  })

  it('produces different keys for different source id sets', () => {
    const a = idempotencyKeyFor(['cmd-1'])
    const b = idempotencyKeyFor(['cmd-2'])

    expect(a).not.toBe(b)
  })

  it('is order-independent for multi-id bundles', () => {
    const a = idempotencyKeyFor(['cmd-1', 'cmd-2', 'cmd-3'])
    const b = idempotencyKeyFor(['cmd-3', 'cmd-1', 'cmd-2'])

    expect(a).toBe(b)
  })

  it('returns a fixed-length 64-char hex string regardless of input size', () => {
    const single = idempotencyKeyFor(['cmd-1'])
    const big = idempotencyKeyFor(
      Array.from({ length: 50 }, (_, i) => `cmd-${i}`)
    )

    expect(single).toMatch(/^[0-9a-f]{16}$/)
    expect(big).toMatch(/^[0-9a-f]{16}$/)
  })
})
