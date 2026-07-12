import { readonly, ref, type Ref } from 'vue'

const STORAGE_KEY = 'tayaway:locale'

// A malformed tag (e.g. "en-US@posix" from a POSIX-configured browser) makes
// every Intl call downstream throw a RangeError mid-render, blanking whole
// components — validate candidates and fall back instead.
function isValidLocale(tag: string): boolean {
  try {
    Intl.getCanonicalLocales(tag)
    return true
  } catch {
    return false
  }
}

function detectInitialLocale(): string {
  // Prefer a locale the user explicitly chose last time over the browser's.
  // localStorage can throw (private-mode quirks, sandbox iframes); fall
  // through silently to the browser locale when it does, so the UI still
  // renders even if persistence is unavailable.
  if (typeof localStorage !== 'undefined') {
    try {
      const stored = localStorage.getItem(STORAGE_KEY)
      if (stored && isValidLocale(stored)) return stored
    } catch {
      /* persistence unavailable; fall through */
    }
  }
  if (
    typeof navigator !== 'undefined' &&
    navigator.language &&
    isValidLocale(navigator.language)
  ) {
    return navigator.language
  }
  return 'en-US'
}

const activeLocale = ref(detectInitialLocale())

/**
 * The active locale for amount formatting (and, in time, dates and numbers).
 * Components read `locale` reactively; a future user-preferences flow will
 * call `setLocale` once we expose the choice in settings. The initial value
 * comes from the last persisted choice, falling back to `navigator.language`.
 */
export function useLocale(): {
  locale: Readonly<Ref<string>>
  setLocale: (locale: string) => void
} {
  return {
    locale: readonly(activeLocale),
    setLocale(locale: string) {
      // Same guard as detection: an invalid tag stored here would crash every
      // downstream Intl call and re-poison startup after reload.
      if (!isValidLocale(locale)) return
      activeLocale.value = locale
      if (typeof localStorage !== 'undefined') {
        try {
          localStorage.setItem(STORAGE_KEY, locale)
        } catch {
          /* persistence unavailable; in-memory only */
        }
      }
    },
  }
}
