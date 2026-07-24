import { describe, it, expect, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import SettingsAppearancePage from './SettingsAppearancePage.vue'
import { useDarkMode } from '@/composables/useDarkMode'

const { setPreference } = useDarkMode()

function selectTheme(wrapper: ReturnType<typeof mount>, value: string) {
  return wrapper.find(`input[type="radio"][value="${value}"]`).setValue(true)
}

describe('SettingsAppearancePage', () => {
  beforeEach(() => {
    setPreference('system')
    localStorage.clear()
  })

  it('checks the option matching the current preference', () => {
    setPreference('dark')
    const wrapper = mount(SettingsAppearancePage)

    const checked = wrapper
      .findAll<HTMLInputElement>('input[type="radio"]')
      .filter((input) => input.element.checked)
      .map((input) => input.element.value)

    expect(checked).toEqual(['dark'])
  })

  it('applies and persists the theme the user picks', async () => {
    const wrapper = mount(SettingsAppearancePage)

    await selectTheme(wrapper, 'dark')

    expect(document.documentElement.classList.contains('dark')).toBe(true)
    expect(localStorage.getItem('dark_mode')).toBe('dark')
  })

  it('falls back to the device setting when automatic is picked', async () => {
    setPreference('dark')
    const wrapper = mount(SettingsAppearancePage)

    await selectTheme(wrapper, 'system')

    // matchMedia is stubbed to report a light device in tests.
    expect(document.documentElement.classList.contains('dark')).toBe(false)
    expect(localStorage.getItem('dark_mode')).toBeNull()
  })
})
