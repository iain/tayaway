import { describe, it, expect, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import SettingsAppearancePage from './SettingsAppearancePage.vue'
import { useDarkMode } from '@/composables/useDarkMode'
import { useLocale } from '@/composables/useLocale'

const { setPreference } = useDarkMode()
const { clearLocale } = useLocale()

function selectTheme(wrapper: ReturnType<typeof mount>, value: string) {
  return wrapper.find(`input[type="radio"][value="${value}"]`).setValue(true)
}

describe('SettingsAppearancePage', () => {
  beforeEach(() => {
    setPreference('system')
    clearLocale()
    localStorage.clear()
  })

  it('checks the option matching the current preference', () => {
    setPreference('dark')
    const wrapper = mount(SettingsAppearancePage)

    const checked = wrapper
      .findAll<HTMLInputElement>('input[type="radio"][name="theme"]')
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

  // The formats group drives useLocale: an explicit pick persists, automatic
  // forgets it and follows the browser again.
  it('applies and persists the date format the user picks', async () => {
    const wrapper = mount(SettingsAppearancePage)

    await wrapper.find('input[type="radio"][value="nl-NL"]').setValue(true)

    expect(useLocale().locale.value).toBe('nl-NL')
    expect(localStorage.getItem('tayaway:locale')).toBe('nl-NL')
  })

  // The sample rides as a description, not inside the label: a screen reader
  // announces "English (US)", not the whole formatted date-and-amount string.
  it('keeps the sample out of the option name, wiring it as a description', () => {
    const wrapper = mount(SettingsAppearancePage)

    const input = wrapper.find('input[type="radio"][value="en-US"]')
    const label = wrapper.find(`label[for="${input.attributes('id')}"]`)
    expect(label.text()).toBe('English (US)')

    const describedBy = input.attributes('aria-describedby')
    const description = wrapper.find(`[id="${describedBy}"]`)
    expect(description.text()).toContain('2026')
  })

  // A persisted tag outside the curated list (an older app version, devtools)
  // must not leave the group with nothing selected while that locale silently
  // drives formatting — surface it as its own checked option.
  it('surfaces a stored locale outside the curated list as a checked option', () => {
    const { setLocale } = useLocale()
    setLocale('fr-FR')

    const wrapper = mount(SettingsAppearancePage)

    const stray = wrapper.find<HTMLInputElement>(
      'input[type="radio"][value="fr-FR"]'
    )
    expect(stray.exists()).toBe(true)
    expect(stray.element.checked).toBe(true)
  })

  it('falls back to the browser locale when format automatic is picked', async () => {
    const wrapper = mount(SettingsAppearancePage)
    await wrapper.find('input[type="radio"][value="nl-NL"]').setValue(true)

    await wrapper.find('input[type="radio"][value="auto"]').setValue(true)

    expect(useLocale().locale.value).toBe(navigator.language)
    expect(localStorage.getItem('tayaway:locale')).toBeNull()
  })
})
