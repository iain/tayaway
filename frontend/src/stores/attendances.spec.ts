import { Scope } from '@/api/scope'
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useAttendancesStore } from './attendances'
import { useObjectPoolStore } from './objectPool'
import { useWorkspaceStore } from './workspace'
import { CommandQueuedError } from '@/stores/commandQueue'
import { makeAttendance, makeGuest } from '@/test/factories'
import type { ApiResponse } from '@/api/client'
import type { ObjectTypeMap } from '@/types/pool'

function okResponse<T>(data: T): ApiResponse<T> {
  return { data, status: 200 }
}

let enqueueImpl: (
  method: string,
  path: string,
  body?: unknown
) => Promise<ApiResponse<unknown>> = async () => okResponse({ objects: [] })

const enqueueSpy = vi.fn()

vi.mock('@/stores/commandQueue', async () => {
  const actual = await vi.importActual<typeof import('@/stores/commandQueue')>(
    '@/stores/commandQueue'
  )
  return {
    ...actual,
    useCommandQueueStore: () => ({
      enqueue: vi.fn().mockImplementation((method, path, body) => {
        enqueueSpy(method, path, body)
        return enqueueImpl(method, path, body)
      }),
    }),
  }
})

vi.mock('@/stores/auth', () => ({
  useAuthStore: () => ({ currentUserId: 'user-1' }),
}))

describe('attendances store', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    localStorage.setItem('current_workspace_id', 'test')
    useWorkspaceStore().initialize(['test'])
    enqueueImpl = async () => okResponse({ objects: [] })
    enqueueSpy.mockClear()
  })

  function seed(...objects: ObjectTypeMap[keyof ObjectTypeMap][]) {
    useObjectPoolStore().importObjects(objects, {
      scope: Scope.workspace('test'),
    })
  }

  describe('submitMemberAttendance', () => {
    it('creates a temp going attendance for the actor optimistically', async () => {
      const pool = useObjectPoolStore()
      const store = useAttendancesStore()

      let duringCall: ObjectTypeMap['attendance'] | undefined
      enqueueImpl = async () => {
        duringCall = pool.getAll('attendance')[0]
        return okResponse({ objects: [] })
      }

      const { attendanceId } = await store.submitMemberAttendance(
        'evt-1',
        'going',
        { days: ['2026-03-03', '2026-03-01'] }
      )

      expect(duringCall).toBeDefined()
      expect(duringCall!.id).toBe(attendanceId)
      expect(duringCall!.userId).toBe('user-1')
      expect(duringCall!.status).toBe('going')
      expect(duringCall!.days).toEqual(['2026-03-01', '2026-03-03'])
      expect(enqueueSpy).toHaveBeenCalledWith(
        'POST',
        '/events/evt-1/attendances',
        expect.objectContaining({
          status: 'going',
          user_id: 'user-1',
          days: ['2026-03-01', '2026-03-03'],
        })
      )
    })

    it('updates the existing row in place, reusing its id', async () => {
      const store = useAttendancesStore()
      const pool = useObjectPoolStore()
      seed(makeAttendance({ id: 'att-9', eventId: 'evt-1', userId: 'user-1' }))

      let statusDuringCall: string | undefined
      enqueueImpl = async () => {
        statusDuringCall = pool.get('attendance', 'att-9')?.status
        return okResponse({ objects: [] })
      }

      const { attendanceId } = await store.submitMemberAttendance(
        'evt-1',
        'declined'
      )

      expect(attendanceId).toBe('att-9')
      expect(statusDuringCall).toBe('declined')
      expect(pool.getAll('attendance').length).toBe(1)
      expect(enqueueSpy).toHaveBeenCalledWith(
        'POST',
        '/events/evt-1/attendances',
        expect.objectContaining({ id: 'att-9', status: 'declined' })
      )
    })

    it('drops days unless going', async () => {
      const pool = useObjectPoolStore()
      const store = useAttendancesStore()

      let duringCall: ObjectTypeMap['attendance'] | undefined
      enqueueImpl = async () => {
        duringCall = pool.getAll('attendance')[0]
        return okResponse({ objects: [] })
      }

      await store.submitMemberAttendance('evt-1', 'declined', {
        days: ['2026-03-01'],
      })

      expect(duringCall!.days).toBeNull()
    })

    it('files on behalf of another member with the actor as filer', async () => {
      const pool = useObjectPoolStore()
      const store = useAttendancesStore()

      let duringCall: ObjectTypeMap['attendance'] | undefined
      enqueueImpl = async () => {
        duringCall = pool.getAll('attendance')[0]
        return okResponse({ objects: [] })
      }

      await store.submitMemberAttendance('evt-1', 'going', {
        onBehalfOfUserId: 'user-2',
      })

      expect(duringCall!.userId).toBe('user-2')
      expect(duringCall!.createdByUserId).toBe('user-1')
    })

    it('removes a differently-id-d temp when the server kept an existing row', async () => {
      const pool = useObjectPoolStore()
      const store = useAttendancesStore()

      enqueueImpl = async () =>
        okResponse({
          objects: [
            makeAttendance({ id: 'server-1', eventId: 'evt-1' }),
          ] as ObjectTypeMap['attendance'][],
        })

      const { attendanceId } = await store.submitMemberAttendance(
        'evt-1',
        'going'
      )

      expect(attendanceId).not.toBe('server-1')
      expect(pool.get('attendance', attendanceId)).toBeUndefined()
    })

    it('keeps the temp when queued offline', async () => {
      const pool = useObjectPoolStore()
      const store = useAttendancesStore()

      enqueueImpl = async () => {
        throw new CommandQueuedError()
      }

      const { attendanceId, queued } = await store.submitMemberAttendance(
        'evt-1',
        'going'
      )

      expect(queued).toBe(true)
      expect(pool.get('attendance', attendanceId)).toBeDefined()
    })
  })

  describe('upsertGuestAttendance', () => {
    it('creates guest and attendance temps together for a new named guest', async () => {
      const pool = useObjectPoolStore()
      const store = useAttendancesStore()

      let guestDuring: ObjectTypeMap['guest'] | undefined
      let attendanceDuring: ObjectTypeMap['attendance'] | undefined
      enqueueImpl = async () => {
        guestDuring = pool.getAll('guest')[0]
        attendanceDuring = pool.getAll('attendance')[0]
        return okResponse({ objects: [] })
      }

      await store.upsertGuestAttendance('evt-1', 'ws-1', {
        name: 'Emma',
        days: ['2026-03-02'],
      })

      expect(guestDuring!.name).toBe('Emma')
      expect(guestDuring!.workspaceId).toBe('ws-1')
      expect(attendanceDuring!.guestId).toBe(guestDuring!.id)
      expect(attendanceDuring!.userId).toBeNull()
      expect(attendanceDuring!.hostUserId).toBe('user-1')
      expect(attendanceDuring!.status).toBe('going')
      expect(enqueueSpy).toHaveBeenCalledWith(
        'POST',
        '/events/evt-1/attendances',
        expect.objectContaining({
          status: 'going',
          days: ['2026-03-02'],
          guest: { id: guestDuring!.id, name: 'Emma' },
        })
      )
    })

    it('revives an existing guest row via update instead of a temp', async () => {
      const pool = useObjectPoolStore()
      const store = useAttendancesStore()
      seed(
        makeGuest({ id: 'guest-7', name: 'Nora' }),
        makeAttendance({
          id: 'att-7',
          eventId: 'evt-1',
          userId: null,
          guestId: 'guest-7',
          hostUserId: 'user-2',
          status: 'declined',
        })
      )

      let statusDuringCall: string | undefined
      enqueueImpl = async () => {
        statusDuringCall = pool.get('attendance', 'att-7')?.status
        return okResponse({ objects: [] })
      }

      const { attendanceId } = await store.upsertGuestAttendance(
        'evt-1',
        'ws-1',
        { guestId: 'guest-7' }
      )

      expect(attendanceId).toBe('att-7')
      expect(statusDuringCall).toBe('going')
      expect(pool.getAll('attendance').length).toBe(1)
      expect(enqueueSpy).toHaveBeenCalledWith(
        'POST',
        '/events/evt-1/attendances',
        expect.objectContaining({ id: 'att-7', guest_id: 'guest-7' })
      )
    })
  })

  describe('removeGuest', () => {
    it('flips the guest row to declined — same verb, no delete', async () => {
      const pool = useObjectPoolStore()
      const store = useAttendancesStore()
      seed(
        makeAttendance({
          id: 'att-7',
          eventId: 'evt-1',
          userId: null,
          guestId: 'guest-7',
          hostUserId: 'user-1',
          status: 'going',
          days: ['2026-03-01'],
        })
      )

      let duringCall: ObjectTypeMap['attendance'] | undefined
      enqueueImpl = async () => {
        duringCall = pool.get('attendance', 'att-7')
        return okResponse({ objects: [] })
      }

      await store.removeGuest('evt-1', 'att-7')

      expect(duringCall?.status).toBe('declined')
      expect(duringCall?.days).toBeNull()
      expect(enqueueSpy).toHaveBeenCalledWith(
        'POST',
        '/events/evt-1/attendances',
        expect.objectContaining({
          id: 'att-7',
          guest_id: 'guest-7',
          status: 'declined',
        })
      )
    })
  })

  describe('resetToPending', () => {
    it('reverts member and guest rows to pending with days cleared', async () => {
      const pool = useObjectPoolStore()
      const store = useAttendancesStore()
      seed(
        makeAttendance({
          id: 'att-1',
          eventId: 'evt-1',
          userId: 'user-2',
          status: 'going',
          days: ['2026-03-01'],
        }),
        makeAttendance({
          id: 'att-2',
          eventId: 'evt-1',
          userId: null,
          guestId: 'guest-7',
          hostUserId: 'user-2',
          status: 'going',
        })
      )

      const statusDuring: Record<string, string | undefined> = {}
      enqueueImpl = async (_method, _path, body) => {
        const id = (body as { id: string }).id
        statusDuring[id] = pool.get('attendance', id)?.status
        return okResponse({ objects: [] })
      }

      await store.resetToPending('evt-1', pool.get('attendance', 'att-1')!)
      await store.resetToPending('evt-1', pool.get('attendance', 'att-2')!)

      expect(statusDuring['att-1']).toBe('pending')
      expect(statusDuring['att-2']).toBe('pending')
      expect(enqueueSpy).toHaveBeenCalledWith(
        'POST',
        '/events/evt-1/attendances',
        expect.objectContaining({
          id: 'att-1',
          user_id: 'user-2',
          status: 'pending',
        })
      )
      expect(enqueueSpy).toHaveBeenCalledWith(
        'POST',
        '/events/evt-1/attendances',
        expect.objectContaining({
          id: 'att-2',
          guest_id: 'guest-7',
          status: 'pending',
        })
      )
    })
  })
})
