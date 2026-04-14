/**
 * Delete runtime caches that may contain user-specific data, while preserving
 * the workbox precache.
 *
 * The workbox precache holds the static app shell (HTML, JS, CSS, fonts,
 * icons) — it has no user data, and clearing it leaves the active service
 * worker with an empty precache, which breaks offline cold-launch on iOS
 * standalone PWAs (see commit 78f696c). User-scoped runtime caches like
 * `api-auth` must still be wiped on logout / session expiry so the next
 * sign-in doesn't see the previous user's data.
 */
export async function clearUserCaches(): Promise<void> {
  if (typeof caches === 'undefined') return
  try {
    const keys = await caches.keys()
    await Promise.all(
      keys
        .filter((k) => !k.startsWith('workbox-precache'))
        .map((k) => caches.delete(k))
    )
  } catch {
    // Caches API may be unavailable
  }
}
