import { describe, it, expect, beforeEach } from 'vitest'
import { useLocale } from './useLocale'

describe('useLocale', () => {
  beforeEach(() => {
    localStorage.clear()
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
