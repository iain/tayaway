/* eslint-disable */
// Service worker fragment imported into the generated PWA worker via
// `workbox.importScripts`. Handles incoming push events and click
// follow-through. The page-side subscription flow lives in
// frontend/src/composables/usePushSubscription.ts; together they
// cover the round-trip from the Web Push payload to a focused browser
// tab.
self.addEventListener('push', (event) => {
  if (!event.data) return

  let payload
  try {
    payload = event.data.json()
  } catch (e) {
    return
  }

  const title = payload.title || 'Tayaway'
  const options = {
    body: payload.body || '',
    icon: '/icon-192.png',
    badge: '/icon-192.png',
    data: { href: payload.href || '/' },
  }

  event.waitUntil(self.registration.showNotification(title, options))
})

self.addEventListener('notificationclick', (event) => {
  event.notification.close()
  const href = (event.notification.data && event.notification.data.href) || '/'
  const targetUrl = new URL(href, self.location.origin).href

  event.waitUntil(
    (async () => {
      const clientList = await self.clients.matchAll({
        type: 'window',
        includeUncontrolled: true,
      })
      // Reuse an open tab on the same origin instead of stacking new ones.
      for (const client of clientList) {
        if (client.url === targetUrl && 'focus' in client) {
          return client.focus()
        }
      }
      const sameOrigin = clientList.find((c) =>
        c.url.startsWith(self.location.origin)
      )
      if (sameOrigin && 'navigate' in sameOrigin) {
        await sameOrigin.navigate(targetUrl)
        return sameOrigin.focus()
      }
      if (self.clients.openWindow) {
        return self.clients.openWindow(targetUrl)
      }
    })()
  )
})
