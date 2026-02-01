import { ref } from 'vue'
import { api } from '@/api/client'
import type { Event, EventsResponse, EventResponse, CreateEventRequest, UpdateEventRequest } from '@/types'

const events = ref<Event[]>([])
const loading = ref(false)
const error = ref<string | null>(null)

export function useEvents() {
  async function fetchEvents(): Promise<Event[]> {
    loading.value = true
    error.value = null
    try {
      const response = await api.get<EventsResponse>('/events')
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
      const response = await api.get<EventResponse>(`/events/${id}`)
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
      const response = await api.post<EventResponse>('/events', data)
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
      const response = await api.put<EventResponse>(`/events/${id}`, data)
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
    } catch (e) {
      error.value = 'Failed to delete event'
      throw e
    } finally {
      loading.value = false
    }
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
  }
}
