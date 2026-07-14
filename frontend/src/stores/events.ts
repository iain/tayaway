import { defineStore } from 'pinia'
import { useMutation } from '@/composables/useMutation'
import { useAuthStore } from './auth'
import { useWorkspaceStore } from './workspace'
import { deviceTimezone } from '@/utils/timezone'
import type { CreateEventRequest, UpdateEventRequest } from '@/types'
import type { PoolApiResponse, PoolEvent } from '@/types/pool'

export const useEventsStore = defineStore('events', () => {
  const { loading, error, create, update, destroy } = useMutation()

  async function createEvent(data: CreateEventRequest) {
    const eventId = crypto.randomUUID()
    const now = new Date().toISOString()
    const tempEvent: PoolEvent = {
      id: eventId,
      objectType: 'event',
      name: data.name,
      description: data.description ?? null,
      startDate: data.startDate ?? null,
      endDate: data.endDate ?? null,
      locationName: data.locationName ?? null,
      latitude: data.latitude ?? null,
      longitude: data.longitude ?? null,
      // Optimistic only — the server resolves the authoritative zone and the
      // pool merge replaces this. Best guess: derived zone, else the
      // workspace default, else this device.
      timezone:
        data.timezone ??
        useWorkspaceStore().currentWorkspace?.timezone ??
        deviceTimezone(),
      workspaceId: useWorkspaceStore().currentWorkspaceId!,
      userId: useAuthStore().currentUserId!,
      datePollId: null,
      rsvpIds: [],
      attendanceIds: [],
      createdAt: now,
      updatedAt: now,
    }

    const result = await create(
      'Failed to create event',
      tempEvent,
      (commandQueue) =>
        commandQueue.enqueue<PoolApiResponse>('POST', '/events', {
          name: data.name,
          description: data.description,
          start_date: data.startDate,
          end_date: data.endDate,
          location_name: data.locationName,
          latitude: data.latitude,
          longitude: data.longitude,
          timezone: data.timezone,
          id: eventId,
          workspace_id: useWorkspaceStore().currentWorkspaceId,
        })
    )
    return { eventId, queued: result.queued }
  }

  async function updateEvent(id: string, data: UpdateEventRequest) {
    await update('Failed to update event', 'event', id, data, (commandQueue) =>
      commandQueue.enqueue<PoolApiResponse>('PUT', `/events/${id}`, {
        name: data.name,
        description: data.description,
        start_date: data.startDate,
        end_date: data.endDate,
        location_name: data.locationName,
        latitude: data.latitude,
        longitude: data.longitude,
        timezone: data.timezone,
      })
    )
  }

  async function deleteEvent(id: string) {
    await destroy('Failed to delete event', 'event', id, (commandQueue) =>
      commandQueue.enqueue('DELETE', `/events/${id}`)
    )
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
