import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { isChunkLoadError } from './index'

describe('isChunkLoadError', () => {
  it('returns true for TypeError with a chunk-load message', () => {
    expect(
      isChunkLoadError(
        new TypeError(
          'Failed to fetch dynamically imported module: https://example.com/assets/chunk-abc.js'
        )
      )
    ).toBe(true)
  })

  it('returns false for TypeError with an unrelated message', () => {
    expect(
      isChunkLoadError(new TypeError('Cannot read properties of undefined'))
    ).toBe(false)
  })

  it('returns true for "Failed to fetch dynamically imported module" errors', () => {
    const error = new Error(
      'Failed to fetch dynamically imported module: https://example.com/assets/EventPage-abc123.js'
    )
    expect(isChunkLoadError(error)).toBe(true)
  })

  it('returns true for "Loading chunk" errors', () => {
    const error = new Error('Loading chunk 42 failed.')
    expect(isChunkLoadError(error)).toBe(true)
  })

  it('returns false for unrelated runtime errors', () => {
    expect(
      isChunkLoadError(new Error('Cannot read properties of undefined'))
    ).toBe(false)
  })

  it('returns false for non-Error values', () => {
    expect(isChunkLoadError('string error')).toBe(false)
    expect(isChunkLoadError(null)).toBe(false)
    expect(isChunkLoadError(undefined)).toBe(false)
    expect(isChunkLoadError(42)).toBe(false)
  })
})

describe('chunk reload guard', () => {
  const reloadKey = 'chunk_load_error_reloaded'
  let reloadSpy: ReturnType<typeof vi.fn>

  function runGuard(error: unknown) {
    if (!isChunkLoadError(error)) return
    if (sessionStorage.getItem(reloadKey)) return
    sessionStorage.setItem(reloadKey, '1')
    window.location.reload()
  }

  beforeEach(() => {
    sessionStorage.removeItem(reloadKey)
    reloadSpy = vi.fn()
    vi.stubGlobal('location', { reload: reloadSpy })
  })

  afterEach(() => {
    vi.unstubAllGlobals()
    sessionStorage.removeItem(reloadKey)
  })

  it('reloads on first chunk load error', () => {
    runGuard(
      new TypeError(
        'Failed to fetch dynamically imported module: https://example.com/chunk.js'
      )
    )
    expect(reloadSpy).toHaveBeenCalledOnce()
  })

  it('does not reload a second time when guard key is already set', () => {
    sessionStorage.setItem(reloadKey, '1')
    runGuard(
      new TypeError(
        'Failed to fetch dynamically imported module: https://example.com/chunk.js'
      )
    )
    expect(reloadSpy).not.toHaveBeenCalled()
  })

  it('does not reload for non-chunk errors', () => {
    runGuard(new Error('Unrelated error'))
    expect(reloadSpy).not.toHaveBeenCalled()
  })
})
