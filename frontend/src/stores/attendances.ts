import { defineStore } from 'pinia'
import { useMutation } from '@/composables/useMutation'
import { useAuthStore } from './auth'
import { useObjectPoolStore } from './objectPool'
import type {
  AttendanceStatus,
  PoolApiResponse,
  PoolAttendance,
  PoolGuest,
} from '@/types/pool'

/**
 * The attendance write path (doc/attendances.md). One row per person per
 * event; status transitions instead of deletes. All writes go through the
 * one upsert endpoint keyed by the subject, so re-adding a removed guest or
 * re-answering after a reset lands on the existing row.
 */
export const useAttendancesStore = defineStore('attendances', () => {
  const { loading, error, create, update } = useMutation()

  function sortedDays(
    status: AttendanceStatus,
    days: string[] | null | undefined
  ): string[] | null {
    // Days carry meaning only when going; the server stores NULL otherwise.
    if (status !== 'going' || !days || days.length === 0) return null
    return [...days].sort()
  }

  function findMemberRow(eventId: string, userId: string) {
    return useObjectPoolStore()
      .getAll('attendance')
      .find((a) => a.eventId === eventId && a.userId === userId)
  }

  function findGuestRow(eventId: string, guestId: string) {
    return useObjectPoolStore()
      .getAll('attendance')
      .find((a) => a.eventId === eventId && a.guestId === guestId)
  }

  /**
   * Upsert an attendance row: optimistic pending-update when the row is
   * already in the pool, optimistic temp create otherwise. The server keeps
   * the existing row's id on conflict, so a temp that raced one is dropped
   * when the response arrives (same as the rsvp path did).
   */
  async function upsertRow(
    eventId: string,
    existing: PoolAttendance | undefined,
    temp: PoolAttendance,
    body: Record<string, unknown>,
    extraTemps: PoolGuest[] = []
  ): Promise<{ attendanceId: string; queued: boolean }> {
    const pool = useObjectPoolStore()

    if (existing) {
      const result = await update(
        'Failed to save attendance',
        'attendance',
        existing.id,
        {
          status: temp.status,
          days: temp.days,
          ...(body['host_user_id'] ? { hostUserId: temp.hostUserId } : {}),
        },
        (commandQueue) =>
          commandQueue.enqueue<PoolApiResponse>(
            'POST',
            `/events/${eventId}/attendances`,
            { ...body, id: existing.id }
          )
      )
      return { attendanceId: existing.id, queued: result.queued }
    } else {
      const result = await create(
        'Failed to save attendance',
        [temp, ...extraTemps],
        (commandQueue) =>
          commandQueue.enqueue<PoolApiResponse>(
            'POST',
            `/events/${eventId}/attendances`,
            { ...body, id: temp.id }
          )
      )
      // If the server found an existing row for this person (stale pool),
      // it kept that row's id — drop the temp so it doesn't linger.
      if (!result.queued) {
        const serverRow = result.data.objects.find(
          (o) => o.objectType === 'attendance'
        )
        if (serverRow && serverRow.id !== temp.id) {
          pool.remove('attendance', temp.id)
        }
      }
      return { attendanceId: temp.id, queued: result.queued }
    }
  }

  /**
   * Create or update a member's attendance. `days` is the explicit day set
   * (ISO YYYY-MM-DD); null/empty/omitted means the whole event.
   */
  async function submitMemberAttendance(
    eventId: string,
    status: AttendanceStatus,
    options: { days?: string[] | null; onBehalfOfUserId?: string } = {}
  ) {
    const actorUserId = useAuthStore().currentUserId!
    const userId = options.onBehalfOfUserId ?? actorUserId
    const days = sortedDays(status, options.days)

    const body = { status, user_id: userId, days }
    const existing = findMemberRow(eventId, userId)
    const now = new Date().toISOString()
    const temp: PoolAttendance = {
      id: crypto.randomUUID(),
      objectType: 'attendance',
      eventId,
      userId,
      guestId: null,
      hostUserId: null,
      status,
      days,
      createdByUserId: actorUserId,
      createdAt: now,
      updatedAt: now,
    }
    return upsertRow(eventId, existing, temp, body)
  }

  /**
   * Add or update a guest's attendance. Pass `guestId` for an existing
   * workspace guest, or `name` to create a new one — guest and attendance
   * are one idempotent command, created in the same transaction server-side.
   */
  async function upsertGuestAttendance(
    eventId: string,
    workspaceId: string,
    options: {
      guestId?: string
      name?: string
      days?: string[] | null
      hostUserId?: string
      status?: AttendanceStatus
    }
  ) {
    const actorUserId = useAuthStore().currentUserId!
    const status = options.status ?? 'going'
    const days = sortedDays(status, options.days)
    const hostUserId = options.hostUserId ?? actorUserId
    const now = new Date().toISOString()

    const existing = options.guestId
      ? findGuestRow(eventId, options.guestId)
      : undefined
    const guestId = options.guestId ?? crypto.randomUUID()

    const body: Record<string, unknown> = options.guestId
      ? { status, days, guest_id: options.guestId }
      : { status, days, guest: { id: guestId, name: options.name } }
    if (options.hostUserId) body['host_user_id'] = options.hostUserId

    const temp: PoolAttendance = {
      id: crypto.randomUUID(),
      objectType: 'attendance',
      eventId,
      userId: null,
      guestId,
      // Optimistic host: the existing row's host stays unless explicitly
      // changed; a fresh row defaults to the actor — mirroring the server.
      hostUserId: options.hostUserId ?? existing?.hostUserId ?? hostUserId,
      status,
      days,
      createdByUserId: actorUserId,
      createdAt: now,
      updatedAt: now,
    }
    const tempGuest: PoolGuest | null = options.guestId
      ? null
      : {
          id: guestId,
          objectType: 'guest',
          workspaceId,
          name: options.name ?? '',
          placeholder: false,
          createdByUserId: actorUserId,
          createdAt: now,
          updatedAt: now,
        }

    return upsertRow(
      eventId,
      existing,
      temp,
      body,
      tempGuest ? [tempGuest] : []
    )
  }

  /** Removing a guest from an event is a decline — the row and the guest's
   *  workspace identity both survive for the next trip. */
  async function removeGuest(eventId: string, attendanceId: string) {
    const pool = useObjectPoolStore()
    const attendance = pool.get('attendance', attendanceId)
    if (!attendance?.guestId) return

    await update(
      'Failed to remove guest',
      'attendance',
      attendanceId,
      { status: 'declined', days: null },
      (commandQueue) =>
        commandQueue.enqueue<PoolApiResponse>(
          'POST',
          `/events/${eventId}/attendances`,
          {
            id: attendanceId,
            guest_id: attendance.guestId,
            status: 'declined',
          }
        )
    )
  }

  /** Date-change reset: keep the person, clear the answer (both member and
   *  guest rows). The server-side owner of this flow arrives in phase 6. */
  async function resetToPending(eventId: string, attendance: PoolAttendance) {
    const subject = attendance.guestId
      ? { guest_id: attendance.guestId }
      : { user_id: attendance.userId }

    await update(
      'Failed to reset attendance',
      'attendance',
      attendance.id,
      { status: 'pending', days: null },
      (commandQueue) =>
        commandQueue.enqueue<PoolApiResponse>(
          'POST',
          `/events/${eventId}/attendances`,
          { id: attendance.id, status: 'pending', ...subject }
        )
    )
  }

  function $reset() {
    loading.value = false
    error.value = null
  }

  return {
    loading,
    error,
    submitMemberAttendance,
    upsertGuestAttendance,
    removeGuest,
    resetToPending,
    $reset,
  }
})
