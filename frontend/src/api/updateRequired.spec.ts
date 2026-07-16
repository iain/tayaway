import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'

// Module state (the one-shot `handling` latch and the reactive flag), so
// each test re-imports a fresh copy via vi.resetModules().

const mockForceUpdateNow = vi.fn()
vi.mock('@/api/autoUpdate', () => ({
  forceUpdateNow: mockForceUpdateNow,
}))

const mockCheckForServiceWorkerUpdate = vi.fn()
vi.mock('@/api/swUpdate', () => ({
  checkForServiceWorkerUpdate: mockCheckForServiceWorkerUpdate,
}))

const mockDisconnect = vi.fn()
vi.mock('@/stores/websocket', () => ({
  useWebSocketStore: vi.fn(() => ({ disconnect: mockDisconnect })),
}))

async function importModule() {
  return await import('./updateRequired')
}

describe('handleUpdateRequired', () => {
  beforeEach(() => {
    vi.resetModules()
    mockForceUpdateNow.mockReset()
    mockCheckForServiceWorkerUpdate.mockReset()
    mockDisconnect.mockReset()
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('raises the blocking update-required flag', async () => {
    const { handleUpdateRequired, updateRequired } = await importModule()
    expect(updateRequired.value).toBe(false)

    await handleUpdateRequired()

    expect(updateRequired.value).toBe(true)
  })

  it('stops the WebSocket so reconnects cannot loop against the gate', async () => {
    const { handleUpdateRequired } = await importModule()

    await handleUpdateRequired()

    expect(mockDisconnect).toHaveBeenCalledOnce()
  })

  it('force-applies any waiting SW update and checks for a new one', async () => {
    const { handleUpdateRequired } = await importModule()

    await handleUpdateRequired()

    expect(mockForceUpdateNow).toHaveBeenCalledOnce()
    expect(mockCheckForServiceWorkerUpdate).toHaveBeenCalledOnce()
  })

  it('runs the flow only once no matter how many 426s arrive', async () => {
    const { handleUpdateRequired, updateRequired } = await importModule()

    await Promise.all([
      handleUpdateRequired(),
      handleUpdateRequired(),
      handleUpdateRequired(),
    ])

    expect(updateRequired.value).toBe(true)
    expect(mockDisconnect).toHaveBeenCalledOnce()
    expect(mockForceUpdateNow).toHaveBeenCalledOnce()
    expect(mockCheckForServiceWorkerUpdate).toHaveBeenCalledOnce()
  })
})
