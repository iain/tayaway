import { describe, it, expect, beforeEach, vi } from 'vitest'
import { useLocale } from './useLocale'

describe('useLocale', () => {
  beforeEach(() => {
    localStorage.clear()
  })

  // A malformed tag (a POSIX-configured browser reports "en-US@posix") must
  // not survive into `locale` — every Intl call downstream would throw a
  // RangeError mid-render. Re-import the module so detectInitialLocale runs
  // against the prepared state.
  it('ignores a stored locale that is not a valid language tag', async () => {
    localStorage.setItem('tayaway:locale', 'en-US@posix')
    vi.resetModules()
    const { useLocale: freshUseLocale } = await import('./useLocale')

    // jsdom's navigator.language is a valid tag, so detection falls through
    // to it rather than the corrupt stored value.
    expect(freshUseLocale().locale.value).toBe(navigator.language)
  })

  it('falls back to en-US when the browser locale is not a valid language tag', async () => {
    const spy = vi
      .spyOn(navigator, 'language', 'get')
      .mockReturnValue('en-US@posix')
    vi.resetModules()
    const { useLocale: freshUseLocale } = await import('./useLocale')

    expect(freshUseLocale().locale.value).toBe('en-US')
    spy.mockRestore()
  })

  it('returns a reactive locale ref', () => {
    const { locale } = useLocale()
    expect(typeof locale.value).toBe('string')
    expect(locale.value.length).toBeGreaterThan(0)
  })

  it('updates the active locale when setLocale is called', () => {
    const { locale, setLocale } = useLocale()
    setLocale('fr-FR')
    expect(locale.value).toBe('fr-FR')
  })

  it('persists the chosen locale to localStorage', () => {
    const { setLocale } = useLocale()
    setLocale('nl-NL')
    expect(localStorage.getItem('tayaway:locale')).toBe('nl-NL')
  })
})
