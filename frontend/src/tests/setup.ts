import { vi } from 'vitest'

// Mock localStorage for Node.js 25+ which provides a built-in localStorage
// that conflicts with jsdom's implementation
const localStorageMock = (() => {
  let store: Record<string, string> = {}
  return {
    getItem: vi.fn((key: string) => store[key] ?? null),
    setItem: vi.fn((key: string, value: string) => {
      store[key] = value
    }),
    removeItem: vi.fn((key: string) => {
      delete store[key]
    }),
    clear: vi.fn(() => {
      store = {}
    }),
    get length() {
      return Object.keys(store).length
    },
    key: vi.fn((index: number) => Object.keys(store)[index] ?? null),
  }
})()
Object.defineProperty(window, 'localStorage', {
  writable: true,
  value: localStorageMock,
})

// jsdom doesn't implement HTMLDialogElement.showModal / close yet. Polyfill
// them as minimal no-ops so components built on native <dialog> (BaseModal)
// can mount and we can dispatch the close/cancel events the real element
// would fire. Guarded so a future jsdom that ships the real methods isn't
// silently overridden.
if (typeof HTMLDialogElement !== 'undefined') {
  if (typeof HTMLDialogElement.prototype.showModal !== 'function') {
    HTMLDialogElement.prototype.showModal = function () {
      if (this.hasAttribute('open')) return
      this.setAttribute('open', '')
    }
  }
  if (typeof HTMLDialogElement.prototype.close !== 'function') {
    HTMLDialogElement.prototype.close = function () {
      if (!this.hasAttribute('open')) return
      this.removeAttribute('open')
      this.dispatchEvent(new Event('close'))
    }
  }
}

// Mock window.matchMedia for components that use it (e.g., useDarkMode)
Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: vi.fn().mockImplementation((query) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: vi.fn(),
    removeListener: vi.fn(),
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    dispatchEvent: vi.fn(),
  })),
})
