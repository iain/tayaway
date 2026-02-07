import { ref } from 'vue'
import { defineStore } from 'pinia'
import { api } from '@/api/client'
import { useObjectPoolStore } from './objectPool'
import type { CreateEventRequest, UpdateEventRequest } from '@/types'
import type { PoolApiResponse } from '@/types/pool'

export const useEventsStore = defineStore('events', () => {
  const loading = ref(false)
  const error = ref<string | null>(null)

  async function fetchEvents(): Promise<void> {
    loading.value = true
    error.value = null
    try {
      const response = await api.get<PoolApiResponse>('/events')
      const pool = useObjectPoolStore()
      pool.importObjects(response.data.objects)
    } catch (e) {
      error.value = 'Failed to fetch events'
      throw e
    } finally {
      loading.value = false
    }
  }

  async function fetchEvent(id: string): Promise<void> {
    loading.value = true
    error.value = null
    try {
      const response = await api.get<PoolApiResponse>(`/events/${id}`)
      const pool = useObjectPoolStore()
      pool.importObjects(response.data.objects)
    } catch (e) {
      error.value = 'Failed to fetch event'
      throw e
    } finally {
      loading.value = false
    }
  }

  async function createEvent(data: CreateEventRequest): Promise<string> {
    loading.value = true
    error.value = null
    try {
      const response = await api.post<PoolApiResponse>('/events', data)
      const pool = useObjectPoolStore()
      pool.importObjects(response.data.objects)

      // Find the new event in the response objects
      const newEvent = response.data.objects.find(o => o.objectType === 'event')
      if (!newEvent) throw new Error('No event in response')
      return newEvent.id
    } catch (e) {
      error.value = 'Failed to create event'
      throw e
    } finally {
      loading.value = false
    }
  }

  async function updateEvent(id: string, data: UpdateEventRequest): Promise<void> {
    loading.value = true
    error.value = null
    try {
      const response = await api.put<PoolApiResponse>(`/events/${id}`, data)
      const pool = useObjectPoolStore()
      pool.importObjects(response.data.objects)
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
    loading.value = false
    error.value = null
  }

  return {
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
