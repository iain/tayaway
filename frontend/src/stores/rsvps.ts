import { defineStore } from 'pinia'
import { nowIso } from '@/utils/date'
import { useMutation } from '@/composables/useMutation'
import { useAuthStore } from './auth'
import { useObjectPoolStore } from './objectPool'
import type { PoolApiResponse, PoolRsvp } from '@/types/pool'
import type { AttendanceEntry } from '@/utils/event'

const entryDate = (entry: AttendanceEntry): string =>
  typeof entry === 'string' ? entry : entry.date

export const useRsvpsStore = defineStore('rsvps', () => {
  const { loading, error, create, update, destroy } = useMutation()

  /**
   * Create or update the subject's RSVP. `attendance` is the explicit
   * "come and go" day set (ISO YYYY-MM-DD); null/empty/omitted means the whole
   * event. The contiguous hull is mirrored onto startDate/endDate to match how
   * the server stores it and to keep legacy readers working.
   */
  async function submitRsvp(
    eventId: string,
    attending: boolean,
    options: {
      attendance?: AttendanceEntry[] | null
      onBehalfOfUserId?: string
    } = {}
  ) {
    const { onBehalfOfUserId } = options
    const pool = useObjectPoolStore()
    const actorUserId = useAuthStore().currentUserId!
    const userId = onBehalfOfUserId ?? actorUserId

    const days =
      attending && options.attendance && options.attendance.length > 0
        ? [...options.attendance].sort((a, b) =>
            entryDate(a).localeCompare(entryDate(b))
          )
        : null
    const startDate = days ? entryDate(days[0]!) : null
    const endDate = days ? entryDate(days[days.length - 1]!) : null

    const body: Record<string, unknown> = {
      attending,
      user_id: userId,
      attendance: days,
    }

    // Check for existing RSVP by the subject user on this event
    const existingRsvp = pool
      .getAll('rsvp')
      .find((r) => r.eventId === eventId && r.userId === userId)

    if (existingRsvp) {
      const result = await update(
        'Failed to submit RSVP',
        'rsvp',
        existingRsvp.id,
        { attending, attendance: days, startDate, endDate },
        (commandQueue) =>
          commandQueue.enqueue<PoolApiResponse>(
            'POST',
            `/events/${eventId}/rsvps`,
            { ...body, id: existingRsvp.id }
          )
      )
      return { rsvpId: existingRsvp.id, queued: result.queued }
    } else {
      const rsvpId = crypto.randomUUID()
      const now = nowIso()
      const tempRsvp: PoolRsvp = {
        id: rsvpId,
        objectType: 'rsvp',
        eventId,
        userId,
        createdByUserId: actorUserId,
        attending,
        attendance: days,
        startDate,
        endDate,
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
