/**
 * Trigger an immediate update check on the active service worker
 * registration. Used when an out-of-band signal (e.g. a different git SHA
 * reported by the server over the WebSocket) tells us a deploy has happened
 * and we don't want to wait for the periodic poll. If a new SW is found,
 * Workbox transitions it to the "waiting" state and registerSW.ts's
 * onNeedRefresh callback surfaces the standard update notification.
 *
 * Kept in its own module so callers (like the WebSocket store) can import
 * it statically without pulling in the `virtual:pwa-register` Vite-virtual
 * module from registerSW.ts, which would break unit tests that don't have
 * the PWA plugin in scope.
 */
export async function checkForServiceWorkerUpdate(): Promise<void> {
  if (!('serviceWorker' in navigator)) return
  try {
    const registration = await navigator.serviceWorker.getRegistration()
    if (registration) await registration.update()
  } catch (err) {
    console.warn('SW update check failed:', err)
  }
}
