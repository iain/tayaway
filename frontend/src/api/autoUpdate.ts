/**
 * Applies a pending service worker update automatically at the first quiet
 * moment instead of prompting the user with an update pill. The caller
 * (registerSW.ts) supplies the apply callback, which activates the waiting
 * SW and reloads — optionally to a target URL when the quiet moment is a
 * route navigation intercepted by the router guard.
 */

type ApplyUpdate = (targetUrl?: string) => void | Promise<void>

/** How long the user must be inactive before we consider it a quiet moment. */
const IDLE_MS = 30_000
/** How often to re-check for a quiet moment. */
const IDLE_CHECK_INTERVAL_MS = 5_000

const ACTIVITY_EVENTS = [
  'pointerdown',
  'keydown',
  'wheel',
  'touchstart',
  'scroll',
] as const

const NON_TEXT_INPUT_TYPES = new Set([
  'button',
  'checkbox',
  'color',
  'file',
  'radio',
  'range',
  'reset',
  'submit',
])

let pendingApply: ApplyUpdate | null = null
let armed = false
let lastActivityAt = 0

function applyNow(targetUrl?: string): void {
  const apply = pendingApply
  pendingApply = null
  void apply?.(targetUrl)
}

function onVisibilityChange(): void {
  if (pendingApply && document.visibilityState === 'hidden') {
    applyNow()
  }
}

function onActivity(): void {
  lastActivityAt = Date.now()
}

/**
 * True when the user plausibly has unsubmitted work on screen: focus in a
 * text-entry control, or an open modal. Focused non-text controls
 * (checkboxes, buttons, …) don't count — clicking one leaves it focused
 * long after the interaction is over.
 */
function isEditing(): boolean {
  if (document.querySelector('dialog[open]')) return true

  const el = document.activeElement
  if (el instanceof HTMLTextAreaElement || el instanceof HTMLSelectElement) {
    return true
  } else if (el instanceof HTMLInputElement) {
    return !NON_TEXT_INPUT_TYPES.has(el.type)
  } else if (el instanceof HTMLElement && el.isContentEditable) {
    return true
  } else {
    return false
  }
}

function onIdleCheck(): void {
  if (pendingApply && !isEditing() && Date.now() - lastActivityAt >= IDLE_MS) {
    applyNow()
  }
}

/** Whether an update is waiting for a quiet moment. Consulted by the router
 * guard, which turns the next in-app navigation into a hard load. */
export function hasPendingUpdate(): boolean {
  return pendingApply !== null
}

/** Apply the pending update right now, landing on targetUrl. No-op when
 * nothing is pending. */
export function applyPendingUpdate(targetUrl: string): void {
  applyNow(targetUrl)
}

export function scheduleAutoUpdate(apply: ApplyUpdate): void {
  pendingApply = apply

  if (document.visibilityState === 'hidden') {
    applyNow()
    return
  }

  if (!armed) {
    armed = true
    // Treat the moment the update arrives as activity, so the user always
    // gets a full idle window before an automatic reload.
    lastActivityAt = Date.now()
    document.addEventListener('visibilitychange', onVisibilityChange)
    for (const event of ACTIVITY_EVENTS) {
      window.addEventListener(event, onActivity, {
        capture: true,
        passive: true,
      })
    }
    setInterval(onIdleCheck, IDLE_CHECK_INTERVAL_MS)
  }
}
