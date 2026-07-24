import { computed, ref, watch } from 'vue'

export type DarkModePreference = 'light' | 'dark' | 'system'

const STORAGE_KEY = 'dark_mode'

// Store media query reference to avoid creating multiple listeners
const darkModeMediaQuery = window.matchMedia('(prefers-color-scheme: dark)')

function getSystemPreference(): boolean {
  return darkModeMediaQuery.matches
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

// Track if listener is already attached to prevent duplicates on HMR
let listenerAttached = false

function handleSystemPreferenceChange(): void {
  if (preference.value === 'system') {
    isDark.value = getSystemPreference()
    updateDarkClass(isDark.value)
  }
}

if (!listenerAttached) {
  darkModeMediaQuery.addEventListener('change', handleSystemPreferenceChange)
  listenerAttached = true
}

watch(preference, (newPref) => {
  if (newPref === 'system') {
    localStorage.removeItem(STORAGE_KEY)
  } else {
    localStorage.setItem(STORAGE_KEY, newPref)
  }
  isDark.value = computeIsDark(newPref)
  updateDarkClass(isDark.value)
})

// Light → dark → automatic → light. A two-state toggle can only ever write
// 'light' or 'dark', which strands anyone on 'system' with no way back except
// the settings page; cycling keeps every state reachable from the keyboard.
const CYCLE: Record<DarkModePreference, DarkModePreference> = {
  light: 'dark',
  dark: 'system',
  system: 'light',
}

export function useDarkMode() {
  const nextPreference = computed(() => CYCLE[preference.value])

  function cycle(): void {
    preference.value = nextPreference.value
  }

  function setPreference(pref: DarkModePreference): void {
    preference.value = pref
  }

  return {
    preference,
    nextPreference,
    isDark,
    cycle,
    setPreference,
  }
}
