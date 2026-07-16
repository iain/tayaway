import { ref } from 'vue'
import { forceUpdateNow } from '@/api/autoUpdate'
import { checkForServiceWorkerUpdate } from '@/api/swUpdate'

/**
 * The server declared this client's PROTOCOL_VERSION unsupported (a 426 on
 * any API request, or an `update_required` WebSocket message). App.vue gates
 * a blocking overlay on this while the service worker update applies.
 */
export const updateRequired = ref(false)

let handling = false

export async function handleUpdateRequired(): Promise<void> {
  // One-shot: every in-flight request 426s at once, and each would tear the
  // socket down and re-trigger the SW machinery again. Never reset — the
  // only exit from this state is the reload that the applied update fires.
  if (handling) return
  handling = true

  updateRequired.value = true

  // Stop reconnecting: the server would just repeat update_required at
  // every attempt until the reload.
  const { useWebSocketStore } = await import('@/stores/websocket')
  useWebSocketStore().disconnect()

  // Apply a waiting update immediately — and if none is waiting yet, check
  // now: when the new SW installs, onNeedRefresh → scheduleAutoUpdate sees
  // the force flag and applies at once instead of waiting for a quiet
  // moment. registerSW.ts reloads on controllerchange (10s backstop).
  forceUpdateNow()
  void checkForServiceWorkerUpdate()
}
