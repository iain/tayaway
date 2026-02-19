import { defineStore } from 'pinia'
import { useMutation } from '@/composables/useMutation'
import { useAuthStore } from './auth'
import { useObjectPoolStore } from './objectPool'
import type { PoolApiResponse, PoolRsvp } from '@/types/pool'

export const useRsvpsStore = defineStore('rsvps', () => {
  const { loading, error, create, update, destroy } = useMutation()

  async function submitRsvp(
    eventId: string,
    attending: boolean,
    startDate?: string | null,
    endDate?: string | null
  ) {
    const pool = useObjectPoolStore()
    const memberId = useAuthStore().currentMemberId!
    const body: Record<string, unknown> = { attending }
    if (startDate) body.start_date = startDate
    if (endDate) body.end_date = endDate

    // Check for existing RSVP by this member on this event
    const existingRsvp = pool
      .getAll('rsvp')
      .find((r) => r.eventId === eventId && r.memberId === memberId)

    if (existingRsvp) {
      const result = await update(
        'Failed to submit RSVP',
        'rsvp',
        existingRsvp.id,
        { attending, startDate: startDate ?? null, endDate: endDate ?? null },
        (commandQueue) =>
          commandQueue.enqueue<PoolApiResponse>(
            'POST',
            `/events/${eventId}/rsvps`,
            body
          )
      )
      return { rsvpId: existingRsvp.id, queued: result.queued }
    } else {
      const rsvpId = crypto.randomUUID()
      const now = new Date().toISOString()
      const tempRsvp: PoolRsvp = {
        id: rsvpId,
        objectType: 'rsvp',
        eventId,
        memberId,
        attending,
        startDate: startDate ?? null,
        endDate: endDate ?? null,
        createdAt: now,
        updatedAt: now,
      }
      const result = await create(
        'Failed to submit RSVP',
        tempRsvp,
        (commandQueue) =>
          commandQueue.enqueue<PoolApiResponse>(
            'POST',
            `/events/${eventId}/rsvps`,
            { ...body, id: rsvpId }
          )
      )
      // If the server used a different RSVP ID (e.g. found an existing RSVP),
      // remove the temp object so it doesn't linger as a phantom.
      if (!result.queued) {
        const serverRsvp = result.data.objects.find(
          (o) => o.objectType === 'rsvp'
        )
        if (serverRsvp && serverRsvp.id !== rsvpId) {
          pool.remove('rsvp', rsvpId)
        }
      }
      return { rsvpId, queued: result.queued }
    }
  }

  async function deleteRsvp(eventId: string, rsvpId: string) {
    await destroy('Failed to delete RSVP', 'rsvp', rsvpId, (commandQueue) =>
      commandQueue.enqueue('DELETE', `/events/${eventId}/rsvps/${rsvpId}`)
    )
  }

  function $reset() {
    loading.value = false
    error.value = null
  }

  return {
    loading,
    error,
    submitRsvp,
    deleteRsvp,
    $reset,
  }
})
