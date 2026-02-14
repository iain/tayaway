import { ref } from 'vue'
import { defineStore } from 'pinia'
import { useCommandQueueStore, CommandQueuedError } from './commandQueue'
import { useWorkspaceStore } from './workspace'
import type { CreateEventRequest, UpdateEventRequest } from '@/types'
import type { PoolApiResponse } from '@/types/pool'

export const useEventsStore = defineStore('events', () => {
  const loading = ref(false)
  const error = ref<string | null>(null)

  async function createEvent(data: CreateEventRequest): Promise<string> {
    loading.value = true
    error.value = null
    try {
      const commandQueue = useCommandQueueStore()
      const workspaceStore = useWorkspaceStore()
      const eventId = crypto.randomUUID()
      const response = await commandQueue.enqueue<PoolApiResponse>(
        'POST',
        '/events',
        {
          ...data,
          id: eventId,
          workspace_id: workspaceStore.currentWorkspaceId,
        }
      )
      const newEvent = response.data.objects.find(
        (o) => o.objectType === 'event'
      )
      if (!newEvent) throw new Error('No event in response')
      return newEvent.id
    } catch (e) {
      if (e instanceof CommandQueuedError) throw e
      error.value = 'Failed to create event'
      throw e
    } finally {
      loading.value = false
    }
  }

  async function updateEvent(
    id: string,
    data: UpdateEventRequest
  ): Promise<void> {
    loading.value = true
    error.value = null
    try {
      const commandQueue = useCommandQueueStore()
      await commandQueue.enqueue<PoolApiResponse>('PUT', `/events/${id}`, data)
    } catch (e) {
      if (e instanceof CommandQueuedError) return
      error.value = 'Failed to update event'
      throw e
    } finally {
      loading.value = false
    }
  }

  async function deleteEvent(id: string): Promise<void> {
    loading.value = true
    error.value = null
    try {
      const commandQueue = useCommandQueueStore()
      await commandQueue.enqueue('DELETE', `/events/${id}`)
    } catch (e) {
      if (e instanceof CommandQueuedError) return
      error.value = 'Failed to delete event'
      throw e
    } finally {
      loading.value = false
    }
  }

  function $reset() {
    loading.value = false
    error.value = null
  }

  return {
    loading,
    error,
    createEvent,
    updateEvent,
    deleteEvent,
    $reset,
  }
})
