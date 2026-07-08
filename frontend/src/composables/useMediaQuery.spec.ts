import { describe, it, expect, vi, afterEach } from 'vitest'
import { effectScope } from 'vue'
import { useMediaQuery } from './useMediaQuery'

const realMatchMedia = window.matchMedia

// A controllable matchMedia stub: lets a test flip `matches` and fire the
// `change` event the composable listens to.
function fakeMatchMedia(initial: boolean) {
  let handler: ((e: MediaQueryListEvent) => void) | null = null
  const mql = {
    matches: initial,
    media: '',
    onchange: null,
    addEventListener: vi.fn(
      (_: string, cb: (e: MediaQueryListEvent) => void) => {
        handler = cb
      }
    ),
    removeEventListener: vi.fn(),
    emit(matches: boolean) {
      mql.matches = matches
      handler?.({ matches } as MediaQueryListEvent)
    },
  }
  window.matchMedia = vi
    .fn()
    .mockReturnValue(mql) as unknown as typeof window.matchMedia
  return mql
}

afterEach(() => {
  window.matchMedia = realMatchMedia
})

describe('useMediaQuery', () => {
  it('reflects the current match at setup', () => {
    fakeMatchMedia(true)
    expect(useMediaQuery('(min-width: 768px)').value).toBe(true)
  })

  it('updates reactively when the query starts matching', () => {
    const mql = fakeMatchMedia(false)
    const matches = useMediaQuery('(min-width: 768px)')
    expect(matches.value).toBe(false)

    mql.emit(true)
    expect(matches.value).toBe(true)
  })

  it('detaches its listener when the owning scope stops', () => {
    const mql = fakeMatchMedia(false)
    const scope = effectScope()
    scope.run(() => useMediaQuery('(min-width: 768px)'))
    expect(mql.removeEventListener).not.toHaveBeenCalled()

    scope.stop()
    expect(mql.removeEventListener).toHaveBeenCalledOnce()
  })
})
