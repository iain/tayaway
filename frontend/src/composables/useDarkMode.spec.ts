import { describe, it, expect, beforeEach } from 'vitest'
import { useDarkMode } from './useDarkMode'

const { preference, setPreference, cycle } = useDarkMode()

describe('useDarkMode', () => {
  beforeEach(() => {
    setPreference('system')
    localStorage.clear()
  })

  it('cycles through every state and back, never stranding automatic', () => {
    setPreference('light')

    const seen = [preference.value]
    for (let i = 0; i < 3; i++) {
      cycle()
      seen.push(preference.value)
    }

    expect(seen).toEqual(['light', 'dark', 'system', 'light'])
  })
})
