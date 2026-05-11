import { ref } from 'vue'
import { rawApi } from '@/api/client'

interface PushConfigResponse {
  vapidPublicKey: string
}

interface RegisterResponse {
  ok: boolean
  vapidPublicKey: string
}

/**
 * Push subscription helper. Browsers gate `pushManager.subscribe` on a
 * granted Notification permission, so the typical flow is: prompt →
 * subscribe → POST credentials to the backend. The composable surfaces
 * the round-trip as one `subscribe()` call plus reactive state for
 * UIs to render permission banners.
 */
export function usePushSubscription() {
  const supported = ref(supportsPush())
  const permission = ref<NotificationPermission | 'unsupported'>(
    supportsPush() ? Notification.permission : 'unsupported'
  )
  const subscribing = ref(false)
  const error = ref<string | null>(null)

  function supportsPush(): boolean {
    return (
      typeof window !== 'undefined' &&
      'serviceWorker' in navigator &&
      'PushManager' in window &&
      'Notification' in window
    )
  }

  function urlBase64ToBuffer(base64String: string): ArrayBuffer {
    const padding = '='.repeat((4 - (base64String.length % 4)) % 4)
    const base64 = (base64String + padding)
      .replace(/-/g, '+')
      .replace(/_/g, '/')
    const rawData = atob(base64)
    const buffer = new ArrayBuffer(rawData.length)
    const view = new Uint8Array(buffer)
    for (let i = 0; i < rawData.length; i += 1) view[i] = rawData.charCodeAt(i)
    return buffer
  }

  function arrayBufferToBase64(buffer: ArrayBuffer): string {
    const bytes = new Uint8Array(buffer)
    let binary = ''
    for (let i = 0; i < bytes.byteLength; i += 1) {
      binary += String.fromCharCode(bytes[i])
    }
    return btoa(binary)
  }

  async function vapidPublicKey(): Promise<string> {
    const { data } = await rawApi.get<PushConfigResponse>(
      '/notifications/push-config'
    )
    if (!data.vapidPublicKey) {
      throw new Error('Push notifications are not configured on the server.')
    }
    return data.vapidPublicKey
  }

  async function getExistingSubscription(): Promise<PushSubscription | null> {
    const registration = await navigator.serviceWorker.ready
    return registration.pushManager.getSubscription()
  }

  async function isSubscribed(): Promise<boolean> {
    if (!supported.value) return false
    const subscription = await getExistingSubscription()
    return subscription !== null
  }

  async function subscribe(): Promise<boolean> {
    if (!supported.value) {
      error.value = 'Push notifications aren’t supported in this browser.'
      return false
    }

    subscribing.value = true
    error.value = null
    try {
      const result = await Notification.requestPermission()
      permission.value = result
      if (result !== 'granted') {
        error.value =
          result === 'denied'
            ? 'You blocked notifications. Re-enable them in your browser settings.'
            : 'Notifications permission was dismissed.'
        return false
      }

      const publicKey = await vapidPublicKey()
      const registration = await navigator.serviceWorker.ready
      const existing = await registration.pushManager.getSubscription()
      if (existing) await existing.unsubscribe()

      const subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToBuffer(publicKey),
      })

      const p256dhKey = subscription.getKey('p256dh')
      const authKey = subscription.getKey('auth')
      if (!p256dhKey || !authKey) {
        throw new Error('Browser did not return push keys.')
      }

      await rawApi.post<RegisterResponse>(
        '/notifications/push-subscriptions',
        {
          endpoint: subscription.endpoint,
          p256dhKey: arrayBufferToBase64(p256dhKey),
          authKey: arrayBufferToBase64(authKey),
        },
        { silent: true }
      )

      return true
    } catch (e) {
      error.value =
        e instanceof Error ? e.message : 'Could not enable push notifications.'
      return false
    } finally {
      subscribing.value = false
    }
  }

  async function unsubscribe(): Promise<void> {
    const subscription = await getExistingSubscription()
    if (!subscription) return
    await rawApi.delete(
      `/notifications/push-subscriptions?endpoint=${encodeURIComponent(subscription.endpoint)}`,
      { silent: true }
    )
    await subscription.unsubscribe()
  }

  return {
    supported,
    permission,
    subscribing,
    error,
    isSubscribed,
    subscribe,
    unsubscribe,
  }
}
