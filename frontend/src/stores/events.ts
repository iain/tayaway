import { ref } from 'vue'
import { defineStore } from 'pinia'
import { api } from '@/api/client'
import { useObjectPoolStore } from './objectPool'
import type { Event, EventsResponse, EventResponse, CreateEventRequest, UpdateEventRequest } from '@/types'
import type { PoolObject } from '@/types/pool'

// Extended response types that include pool objects
interface EventsResponseWithPool extends EventsResponse {
  objects?: PoolObject[]
}

interface EventResponseWithPool extends EventResponse {
  objects?: PoolObject[]
}

export const useEventsStore = defineStore('events', () => {
  // Event list for list views - kept separate from pool for list-specific ordering
  const events = ref<Event[]>([])
  const loading = ref(false)
  const error = ref<string | null>(null)

  async function fetchEvents(): Promise<Event[]> {
    loading.value = true
    error.value = null
    try {
      const response = await api.get<EventsResponseWithPool>('/events')

      // Import objects to pool if present
      if (response.data.objects) {
        const pool = useObjectPoolStore()
        pool.importObjects(response.data.objects)
      }

      events.value = response.data.events
      return events.value
    } catch (e) {
      error.value = 'Failed to fetch events'
      throw e
    } finally {
      loading.value = false
    }
  }

  async function fetchEvent(id: string): Promise<Event> {
    loading.value = true
    error.value = null
    try {
      const response = await api.get<EventResponseWithPool>(`/events/${id}`)

      // Import objects to pool if present
      if (response.data.objects) {
        const pool = useObjectPoolStore()
        pool.importObjects(response.data.objects)
      }

      return response.data.event
    } catch (e) {
      error.value = 'Failed to fetch event'
      throw e
    } finally {
      loading.value = false
    }
  }

  async function createEvent(data: CreateEventRequest): Promise<Event> {
    loading.value = true
    error.value = null
    try {
      const response = await api.post<EventResponseWithPool>('/events', data)

      // Import objects to pool if present
      if (response.data.objects) {
        const pool = useObjectPoolStore()
        pool.importObjects(response.data.objects)
      }

      const newEvent = response.data.event
      events.value = [...events.value, newEvent]
      return newEvent
    } catch (e) {
      error.value = 'Failed to create event'
      throw e
    } finally {
      loading.value = false
    }
  }

  async function updateEvent(id: string, data: UpdateEventRequest): Promise<Event> {
    loading.value = true
    error.value = null
    try {
      const response = await api.put<EventResponseWithPool>(`/events/${id}`, data)

      // Import objects to pool if present
      if (response.data.objects) {
        const pool = useObjectPoolStore()
        pool.importObjects(response.data.objects)
      }

      const updatedEvent = response.data.event
      events.value = events.value.map(e => e.id === id ? updatedEvent : e)
      return updatedEvent
    } catch (e) {
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
      await api.delete(`/events/${id}`)
      events.value = events.value.filter(e => e.id !== id)

      // Also remove from pool
      const pool = useObjectPoolStore()
      pool.remove('event', id)
    } catch (e) {
      error.value = 'Failed to delete event'
      throw e
    } finally {
      loading.value = false
    }
  }

  function $reset() {
    events.value = []
    loading.value = false
    error.value = null
  }

  return {
    events,
    loading,
    error,
    fetchEvents,
    fetchEvent,
    createEvent,
    updateEvent,
    deleteEvent,
    $reset,
  }
})
