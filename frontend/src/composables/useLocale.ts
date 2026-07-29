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

// The locale the user explicitly chose in settings, or null when they never
// did. localStorage can throw (private-mode quirks, sandbox iframes); fall
// through silently so the UI still renders even if persistence is unavailable.
function detectStoredLocale(): string | null {
  if (typeof localStorage !== 'undefined') {
    try {
      const stored = localStorage.getItem(STORAGE_KEY)
      if (stored && isValidLocale(stored)) return stored
    } catch {
      /* persistence unavailable; fall through */
    }
  }
  return null
}

function detectBrowserLocale(): string {
  if (
    typeof navigator !== 'undefined' &&
    navigator.language &&
    isValidLocale(navigator.language)
  ) {
    return navigator.language
  }
  return 'en-US'
}

/**
 * What "Automatic" resolves to — the browser's language. Exposed so the
 * settings picker can show what the automatic option would look like even
 * while an explicit choice is active.
 */
export const browserLocale = detectBrowserLocale()

const initialChoice = detectStoredLocale()
const preference = ref<string | null>(initialChoice)
const activeLocale = ref(initialChoice ?? browserLocale)

/**
 * The active locale for date and amount formatting. Components read `locale`
 * reactively; the appearance settings page calls `setLocale`/`clearLocale`
 * when the user picks a format. `locale` always resolves to something
 * formattable — the persisted choice when there is one, the browser's
 * language otherwise — while `preference` distinguishes "chose this" (a tag)
 * from "automatic" (null) for the picker's selected state.
 */
export function useLocale(): {
  locale: Readonly<Ref<string>>
  preference: Readonly<Ref<string | null>>
  setLocale: (locale: string) => void
  clearLocale: () => void
} {
  return {
    locale: readonly(activeLocale),
    preference: readonly(preference),
    setLocale(locale: string) {
      // Same guard as detection: an invalid tag stored here would crash every
      // downstream Intl call and re-poison startup after reload.
      if (!isValidLocale(locale)) return
      preference.value = locale
      activeLocale.value = locale
      if (typeof localStorage !== 'undefined') {
        try {
          localStorage.setItem(STORAGE_KEY, locale)
        } catch {
          /* persistence unavailable; in-memory only */
        }
      }
    },
    clearLocale() {
      preference.value = null
      activeLocale.value = detectBrowserLocale()
      if (typeof localStorage !== 'undefined') {
        try {
          localStorage.removeItem(STORAGE_KEY)
        } catch {
          /* persistence unavailable; in-memory only */
        }
      }
    },
  }
}
