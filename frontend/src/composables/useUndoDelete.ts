import { useObjectPoolStore } from '@/stores/objectPool'
import { useCommandQueueStore, CommandQueuedError } from '@/stores/commandQueue'
import { useNotificationsStore } from '@/stores/notifications'
import type { ObjectType } from '@/types/pool'

const UNDO_WINDOW_MS = 5000

/**
 * Provides an undo-based deletion flow: optimistically removes the object from
 * the pool, shows a toast with "Undo", then fires the actual DELETE after the
 * undo window expires. If the user clicks Undo, the objects are restored
 * without ever hitting the server.
 */
export function useUndoDelete() {
  function undoableDelete(options: {
    objectType: ObjectType
    objectId: string
    message: string
    apiPath: string
  }) {
    const pool = useObjectPoolStore()
    const notifications = useNotificationsStore()

    // 1. Optimistically remove from pool (including child objects)
    const removedObjects = pool.cascadeRemove(
      options.objectType,
      options.objectId
    )
    if (removedObjects.length === 0) return

    // 2. Track whether undo was clicked
    let undone = false

    // 3. Show toast with Undo action
    notifications.showInfo(options.message, {
      actionLabel: 'Undo',
      action: () => {
        undone = true
        pool.restore(removedObjects)
      },
      duration: UNDO_WINDOW_MS,
    })

    // 4. After undo window, fire the actual API delete. The destroy ref
    // rides along so a permanently-failed replay restores the objects
    // instead of stranding the local deletion.
    setTimeout(async () => {
      if (undone) return
      try {
        const commandQueue = useCommandQueueStore()
        await commandQueue.enqueue('DELETE', options.apiPath, undefined, {
          kind: 'destroy',
          removed: removedObjects,
        })
      } catch (e) {
        if (e instanceof CommandQueuedError) return
        pool.restore(removedObjects)
        notifications.showError("Couldn't delete — the item has been restored.")
      }
    }, UNDO_WINDOW_MS)
  }

  return { undoableDelete }
}
