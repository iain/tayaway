import { describe, it, expect, vi, beforeEach } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'

// Capture the body passed to commandQueue.enqueue so tests can assert on it
const enqueueMock = vi.fn().mockResolvedValue({ data: { objects: [] } })

vi.mock('@/stores/commandQueue', () => ({
  CommandQueuedError: class CommandQueuedError extends Error {
    constructor() {
      super('Command queued for later execution')
      this.name = 'CommandQueuedError'
    }
  },
  useCommandQueueStore: () => ({ enqueue: enqueueMock }),
}))

vi.mock('@/stores/objectPool', () => ({
  useObjectPoolStore: () => ({
    getAll: vi.fn().mockReturnValue([]),
    set: vi.fn(),
    remove: vi.fn(),
    addPending: vi.fn().mockReturnValue('pending-id'),
    removePending: vi.fn(),
    cascadeRemove: vi.fn().mockReturnValue([]),
    importObjects: vi.fn(),
  }),
}))

vi.mock('@/stores/auth', () => ({
  useAuthStore: () => ({ currentUserId: 'user-1' }),
}))

// useMutation derives the scope for optimistic temp objects from the active
// workspace and throws if none is set; this suite only exercises body
// shaping, so a stub workspace is enough.
vi.mock('@/stores/workspace', () => ({
  useWorkspaceStore: () => ({ currentWorkspaceId: 'test' }),
}))

vi.mock('@/api/commandDb', () => ({
  addCommand: vi.fn(),
  removeCommand: vi.fn(),
  getPendingCommands: vi.fn().mockResolvedValue([]),
  count: vi.fn().mockResolvedValue(0),
  clearAll: vi.fn(),
}))

const { useRsvpsStore } = await import('@/stores/rsvps')

describe('useRsvpsStore — submitRsvp body building', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    enqueueMock.mockClear()
  })

  it('sends null attendance when attending the whole event', async () => {
    const store = useRsvpsStore()

    await store.submitRsvp('evt-1', true)

    expect(enqueueMock).toHaveBeenCalledOnce()
    const [, , body] = enqueueMock.mock.calls[0]
    expect(body).toMatchObject({ attending: true, attendance: null })
  })

  it('sends the sorted attendance day set in the request body', async () => {
    const store = useRsvpsStore()

    await store.submitRsvp('evt-1', true, {
      attendance: ['2026-03-12', '2026-03-10'],
    })

    expect(enqueueMock).toHaveBeenCalledOnce()
    const [, , body] = enqueueMock.mock.calls[0]
    expect(body).toMatchObject({
      attending: true,
      attendance: ['2026-03-10', '2026-03-12'],
    })
  })

  it('sends null attendance when declining', async () => {
    const store = useRsvpsStore()

    await store.submitRsvp('evt-1', false, { attendance: ['2026-03-10'] })

    expect(enqueueMock).toHaveBeenCalledOnce()
    const [, , body] = enqueueMock.mock.calls[0]
    expect(body).toMatchObject({ attending: false, attendance: null })
  })
})
