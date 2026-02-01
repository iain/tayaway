import { ref, watch } from 'vue'

type DarkModePreference = 'light' | 'dark' | 'system'

const STORAGE_KEY = 'dark_mode'

function getSystemPreference(): boolean {
  return window.matchMedia('(prefers-color-scheme: dark)').matches
}

function updateDarkClass(dark: boolean): void {
  if (dark) {
    document.documentElement.classList.add('dark')
  } else {
    document.documentElement.classList.remove('dark')
  }
}

function computeIsDark(pref: DarkModePreference): boolean {
  if (pref === 'system') {
    return getSystemPreference()
  }
  return pref === 'dark'
}

function getInitialPreference(): DarkModePreference {
  const saved = localStorage.getItem(STORAGE_KEY)
  if (saved === 'light' || saved === 'dark') {
    return saved
  }
  return 'system'
}

const preference = ref<DarkModePreference>(getInitialPreference())
const isDark = ref(computeIsDark(preference.value))

updateDarkClass(isDark.value)

window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
  if (preference.value === 'system') {
    isDark.value = getSystemPreference()
    updateDarkClass(isDark.value)
  }
})

watch(preference, (newPref) => {
  if (newPref === 'system') {
    localStorage.removeItem(STORAGE_KEY)
  } else {
    localStorage.setItem(STORAGE_KEY, newPref)
  }
  isDark.value = computeIsDark(newPref)
  updateDarkClass(isDark.value)
})

export function useDarkMode() {
  function toggle(): void {
    preference.value = isDark.value ? 'light' : 'dark'
  }

  function setPreference(pref: DarkModePreference): void {
    preference.value = pref
  }

  return {
    preference,
    isDark,
    toggle,
    setPreference,
  }
}
