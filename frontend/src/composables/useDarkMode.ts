import { ref, watch, onMounted } from 'vue'

type DarkModePreference = 'light' | 'dark' | 'system'

const STORAGE_KEY = 'dark_mode'

const preference = ref<DarkModePreference>('system')
const isDark = ref(false)

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

export function useDarkMode() {
  onMounted(() => {
    const saved = localStorage.getItem(STORAGE_KEY) as DarkModePreference | null
    if (saved === 'light' || saved === 'dark') {
      preference.value = saved
    } else {
      preference.value = 'system'
    }
    isDark.value = computeIsDark(preference.value)
    updateDarkClass(isDark.value)

    const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)')
    mediaQuery.addEventListener('change', () => {
      if (preference.value === 'system') {
        isDark.value = getSystemPreference()
        updateDarkClass(isDark.value)
      }
    })
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
