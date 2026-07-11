---
name: verify
description: Verify frontend changes in the built PWA, including service-worker update flows, by driving a production build in a browser.
---

# Verifying frontend changes in the running PWA

For plain UI changes, `mise run dev` and the e2e servers are enough. The
recipe below is for changes to the **service worker / update flow**
(`registerSW.ts`, `src/api/autoUpdate.ts`, `src/api/swUpdate.ts`), which only
exist in production builds.

## Recipe: drive a SW update end-to-end

1. Build and serve the production bundle (SW only exists in builds):

   ```sh
   cd frontend && aube exec vite build && aube exec vite preview   # :5175
   ```

2. Load `http://localhost:5175/login` (works unauthenticated; API proxy
   errors in the console are harmless without a backend). Wait for
   `navigator.serviceWorker.ready` and confirm `controller` is set.

3. Ship a "new version": add `<meta name="verify-marker" content="vN" />` to
   `frontend/index.html`, rebuild. The marker changes the precache manifest,
   so the SW updates; read the meta tag after a reload to know which version
   the page is on. **Revert index.html when done.**

4. Trigger detection from the page: `(await navigator.serviceWorker
   .getRegistration()).update()` — the same call the app's hourly poll,
   visibility handler, and WebSocket git-SHA nudge make. A second or two
   later `registration.waiting` is `"installed"` and `onNeedRefresh` has
   fired.

5. Observe the update applying. Evidence: the marker meta content, plus
   `performance.getEntriesByType('navigation')[0].type === 'reload'` and
   `registration.waiting === null`.

## Gotchas learned the hard way

- **Headless tab-switching does not change `document.visibilityState`** —
  the app's visibility-based update check won't fire from `browser_tabs`.
  To exercise hidden-tab behaviour, override it in the page:
  `Object.defineProperty(document, 'visibilityState', { configurable: true,
  get: () => 'hidden' })` then dispatch `visibilitychange`.
- **The login page autofocuses its email input**, which blocks the
  idle-update path by design. Blur it first when testing idle behaviour.
- **A reload issued before `controllerchange`** is served by the *old* SW's
  precache — the page reloads and is still the old version. Any reload logic
  must wait for `controllerchange` (see registerSW.ts).
- **workbox-window classifies updates found >60s after registration as
  "external"**, and vite-plugin-pwa's `controlling` listener / `onNeedReload`
  only fires when `event.isUpdate` is true (page was controlled at
  registration). Don't rely on those hooks for reload timing.
- Between cycles, reset to a clean slate from the page: unregister the SW,
  delete all `caches` keys, then hard-navigate.
