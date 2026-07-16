import { defineStore } from 'pinia'
import { nowIso } from '@/utils/date'
import { useMutation } from '@/composables/useMutation'
import { useAuthStore } from './auth'
import type {
  PoolApiResponse,
  PoolChoreRoster,
  PoolChore,
  PoolChoreAssignment,
} from '@/types/pool'

export const useChoreRostersStore = defineStore('choreRosters', () => {
  const { loading, error, create, mutate, update, destroy } = useMutation()

  async function createRoster(eventId: string) {
    const rosterId = crypto.randomUUID()
    const now = nowIso()
    const tempRoster: PoolChoreRoster = {
      id: rosterId,
      objectType: 'choreRoster',
      eventId,
      userId: useAuthStore().currentUserId ?? null,
      choreIds: [],
      createdAt: now,
      updatedAt: now,
    }

    const result = await create(
      'Failed to create chore roster',
      tempRoster,
      (commandQueue) =>
        commandQueue.enqueue<PoolApiResponse>('POST', '/chore-rosters', {
          event_id: eventId,
          id: rosterId,
        })
    )
    return { rosterId, queued: result.queued }
  }

  async function addChore(
    rosterId: string,
    name: string,
    peoplePerDay: number,
    time: string | null = null
  ) {
    const choreId = crypto.randomUUID()
    const now = nowIso()
    const tempChore: PoolChore = {
      id: choreId,
      objectType: 'chore',
      choreRosterId: rosterId,
      name,
      peoplePerDay,
      position: Date.now(),
      time: time || null,
      assignmentIds: [],
      createdAt: now,
      updatedAt: now,
    }

    const body: Record<string, unknown> = {
      name,
      people_per_day: peoplePerDay,
      id: choreId,
    }
    if (time) body.time = time

    const result = await create(
      'Failed to add chore',
      tempChore,
      (commandQueue) =>
        commandQueue.enqueue<PoolApiResponse>(
          'POST',
          `/chore-rosters/${rosterId}/chores`,
          body
        )
    )
    return { choreId, queued: result.queued }
  }

  async function updateChore(
    rosterId: string,
    choreId: string,
    changes: {
      name?: string
      peoplePerDay?: number
      position?: number
      time?: string | null
    }
  ) {
    const apiChanges: Record<string, unknown> = {}
    if (changes.name !== undefined) apiChanges.name = changes.name
    if (changes.peoplePerDay !== undefined)
      apiChanges.people_per_day = changes.peoplePerDay
    if (changes.position !== undefined) apiChanges.position = changes.position
    // null clears the time; the server reads a blank string as "clear".
    if (changes.time !== undefined) apiChanges.time = changes.time ?? ''

    await update(
      'Failed to update chore',
      'chore',
      choreId,
      changes,
      (commandQueue) =>
        commandQueue.enqueue<PoolApiResponse>(
          'PUT',
          `/chore-rosters/${rosterId}/chores/${choreId}`,
          apiChanges
        )
    )
  }

  async function deleteChore(rosterId: string, choreId: string) {
    await destroy('Failed to delete chore', 'chore', choreId, (commandQueue) =>
      commandQueue.enqueue(
        'DELETE',
        `/chore-rosters/${rosterId}/chores/${choreId}`
      )
    )
  }

  async function createAssignment(
    rosterId: string,
    choreId: string,
    // The attendance behind the holder is what the server keys on; userId
    // rides along so the optimistic chip renders before the response lands.
    holder: { attendanceId: string; userId: string | null },
    date: string
  ) {
    const assignmentId = crypto.randomUUID()
    const now = nowIso()
    const tempAssignment: PoolChoreAssignment = {
      id: assignmentId,
      objectType: 'choreAssignment',
      choreId,
      attendanceId: holder.attendanceId,
      userId: holder.userId,
      date,
      pinned: true,
      note: null,
      createdAt: now,
      updatedAt: now,
    }

    const result = await create(
      'Failed to create assignment',
      tempAssignment,
      (commandQueue) =>
        commandQueue.enqueue<PoolApiResponse>(
          'POST',
          `/chore-rosters/${rosterId}/assignments`,
          {
            chore_id: choreId,
            attendance_id: holder.attendanceId,
            date,
            id: assignmentId,
          }
        )
    )
    return { assignmentId, queued: result.queued }
  }

  async function updateAssignment(
    rosterId: string,
    assignmentId: string,
    changes: {
      note?: string
      pinned?: boolean
      attendanceId?: string
      // Optimistic-only mirror of the attendance's member; not sent — the
      // server derives it from attendance_id.
      userId?: string | null
    }
  ) {
    const apiChanges: Record<string, unknown> = {}
    if (changes.note !== undefined) apiChanges.note = changes.note
    if (changes.attendanceId !== undefined)
      apiChanges.attendance_id = changes.attendanceId
    if (changes.pinned !== undefined) apiChanges.pinned = changes.pinned

    await update(
      'Failed to update assignment',
      'choreAssignment',
      assignmentId,
      changes,
      (commandQueue) =>
        commandQueue.enqueue<PoolApiResponse>(
          'PUT',
          `/chore-rosters/${rosterId}/assignments/${assignmentId}`,
          apiChanges
        )
    )
  }

  async function deleteAssignment(rosterId: string, assignmentId: string) {
    await destroy(
      'Failed to delete assignment',
      'choreAssignment',
      assignmentId,
      (commandQueue) =>
        commandQueue.enqueue(
          'DELETE',
          `/chore-rosters/${rosterId}/assignments/${assignmentId}`
        )
    )
  }

  async function deleteRoster(rosterId: string) {
    await destroy(
      'Failed to delete roster',
      'choreRoster',
      rosterId,
      (commandQueue) =>
        commandQueue.enqueue('DELETE', `/chore-rosters/${rosterId}`)
    )
  }

  async function autofill(rosterId: string) {
    await mutate('Failed to autofill roster', (commandQueue) =>
      commandQueue.enqueue<PoolApiResponse>(
        'POST',
        `/chore-rosters/${rosterId}/autofill`
      )
    )
  }

  async function reassignStale(rosterId: string) {
    await mutate('Failed to reassign chores', (commandQueue) =>
      commandQueue.enqueue<PoolApiResponse>(
        'POST',
        `/chore-rosters/${rosterId}/reassign-stale`
      )
    )
  }

  async function clearUnpinned(rosterId: string) {
    await mutate('Failed to clear assignments', (commandQueue) =>
      commandQueue.enqueue<PoolApiResponse>(
        'POST',
        `/chore-rosters/${rosterId}/clear-unpinned`
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
    createRoster,
    addChore,
    updateChore,
    deleteChore,
    deleteRoster,
    createAssignment,
    updateAssignment,
    deleteAssignment,
    autofill,
    reassignStale,
    clearUnpinned,
    $reset,
  }
})
