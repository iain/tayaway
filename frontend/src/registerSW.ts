import { registerSW } from 'virtual:pwa-register'
import { scheduleAutoUpdate } from '@/api/autoUpdate'

export function registerServiceWorker(): void {
  // Where to land once the new SW takes control: a target URL when the quiet
  // moment was an intercepted route navigation, otherwise reload in place.
  let updateTargetUrl: string | undefined
  let navigated = false

  function navigateToNewVersion(): void {
    if (navigated) return
    navigated = true
    if (updateTargetUrl) {
      window.location.assign(updateTargetUrl)
    } else {
      window.location.reload()
    }
  }

  const updateSW = registerSW({
    immediate: true,
    onNeedRefresh() {
      // Apply the update automatically at the next quiet moment (tab hidden,
      // route navigation, or user idle) instead of prompting with a pill.
      scheduleAutoUpdate(async (targetUrl) => {
        updateTargetUrl = targetUrl

        // Reload only once the new SW controls the page — any earlier and
        // the old SW can serve the stale precache one more time, leaving the
        // user on the old version despite the reload. controllerchange is
        // that moment. (The plugin's own onNeedReload hook is not enough: it
        // is skipped when workbox-window classifies the update as "external",
        // which is every update found more than a minute after page load on
        // a page that started uncontrolled.)
        navigator.serviceWorker.addEventListener(
          'controllerchange',
          navigateToNewVersion,
          { once: true }
        )
        // Backstop in case controllerchange never fires (e.g. the waiting SW
        // was already activated by another tab). Landing on the old version
        // is fine: onNeedRefresh fires again there and we retry.
        setTimeout(navigateToNewVersion, 10_000)

        try {
          await updateSW() // tells the waiting SW to skipWaiting
        } catch {
          navigateToNewVersion()
        }
      })
    },
    // Keep the plugin's controlling-listener from hard-reloading and losing
    // updateTargetUrl in the cases where it does fire.
    onNeedReload: navigateToNewVersion,
    onRegisteredSW(_url, registration) {
      if (!registration) return

      const onUpdateError = (err: unknown) =>
        console.warn('SW update failed:', err)

      // Check for updates every 60 minutes
      setInterval(
        () => registration.update().catch(onUpdateError),
        60 * 60 * 1000
      )

      // Check for updates when tab becomes visible (throttled to 30s)
      let lastVisibilityCheck = 0
      document.addEventListener('visibilitychange', () => {
        if (document.visibilityState !== 'visible') return
        const now = Date.now()
        if (now - lastVisibilityCheck < 30_000) return
        lastVisibilityCheck = now
        registration.update().catch(onUpdateError)
      })
    },
  })
}

// Re-export so existing consumers (and docs pointing at registerSW.ts) keep
// working. The real definition lives in @/api/swUpdate so it can be imported
// without dragging `virtual:pwa-register` into the module graph.
export { checkForServiceWorkerUpdate } from '@/api/swUpdate'
