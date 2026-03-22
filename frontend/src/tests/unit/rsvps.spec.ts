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

  it('includes null startDate and endDate in the request body when clearing dates', async () => {
    const store = useRsvpsStore()

    await store.submitRsvp('evt-1', true, null, null)

    expect(enqueueMock).toHaveBeenCalledOnce()
    const [, , body] = enqueueMock.mock.calls[0]
    expect(body).toMatchObject({
      attending: true,
      start_date: null,
      end_date: null,
    })
  })

  it('omits startDate and endDate from the body when not provided', async () => {
    const store = useRsvpsStore()

    await store.submitRsvp('evt-1', true)

    expect(enqueueMock).toHaveBeenCalledOnce()
    const [, , body] = enqueueMock.mock.calls[0]
    expect(body).not.toHaveProperty('start_date')
    expect(body).not.toHaveProperty('end_date')
  })

  it('includes non-null dates in the request body', async () => {
    const store = useRsvpsStore()

    await store.submitRsvp('evt-1', true, '2026-03-10', '2026-03-12')

    expect(enqueueMock).toHaveBeenCalledOnce()
    const [, , body] = enqueueMock.mock.calls[0]
    expect(body).toMatchObject({
      attending: true,
      start_date: '2026-03-10',
      end_date: '2026-03-12',
    })
  })
})
