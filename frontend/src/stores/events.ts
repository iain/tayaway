import { ref, computed } from 'vue'
import { defineStore } from 'pinia'
import { api } from '@/api/client'
import type { Event, EventsResponse, EventResponse, CreateEventRequest, UpdateEventRequest, Vote, VoteSummary } from '@/types'

export const useEventsStore = defineStore('events', () => {
  const events = ref<Event[]>([])
  const eventCache = ref<Record<string, Event>>({})
  const loading = ref(false)
  const error = ref<string | null>(null)

  const getEvent = computed(() => (id: string): Event | undefined => {
    return eventCache.value[id]
  })

  async function fetchEvents(): Promise<Event[]> {
    loading.value = true
    error.value = null
    try {
      const response = await api.get<EventsResponse>('/events')
      events.value = response.data.events
      // Populate cache with list data
      for (const event of events.value) {
        eventCache.value[event.id] = event
      }
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
      const event = response.data.event
      eventCache.value[id] = event
      return event
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
      eventCache.value[newEvent.id] = newEvent
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
      eventCache.value[id] = updatedEvent
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
      delete eventCache.value[id]
    } catch (e) {
      error.value = 'Failed to delete event'
      throw e
    } finally {
      loading.value = false
    }
  }

  function updateEventVote(eventId: string, dateRangeId: string, vote: Vote): void {
    const event = eventCache.value[eventId]
    if (!event) return

    const dateRange = event.date_ranges.find(dr => dr.id === dateRangeId)
    if (!dateRange) return

    // Update or add the vote
    const existingIndex = dateRange.votes.findIndex(v => v.user_id === vote.user_id)
    if (existingIndex >= 0) {
      dateRange.votes[existingIndex] = vote
    } else {
      dateRange.votes.push(vote)
    }

    // Recalculate vote summary
    dateRange.vote_summary = calculateVoteSummary(dateRange.votes)
  }

  function calculateVoteSummary(votes: Vote[]): VoteSummary {
    return {
      yes: votes.filter(v => v.response === 'yes').length,
      no: votes.filter(v => v.response === 'no').length,
      preferably_not: votes.filter(v => v.response === 'preferably_not').length,
      total: votes.length,
    }
  }

  function $reset() {
    events.value = []
    eventCache.value = {}
    loading.value = false
    error.value = null
  }

  return {
    events,
    loading,
    error,
    getEvent,
    fetchEvents,
    fetchEvent,
    createEvent,
    updateEvent,
    updateEventVote,
    deleteEvent,
    $reset,
  }
})
