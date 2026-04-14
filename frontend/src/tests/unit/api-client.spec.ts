import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'

// Must mock stores before importing the client module
vi.mock('@/stores', () => ({
  useObjectPoolStore: () => ({
    importObjects: vi.fn(),
    remove: vi.fn(),
  }),
  useNotificationsStore: () => ({
    showError: vi.fn(),
  }),
}))

// Import after mocks are set up
const { rawApi } = await import('@/api/client')

/** Returns a Promise that rejects with AbortError when the given signal fires. */
function hangingFetch(signal: AbortSignal | undefined): Promise<Response> {
  return new Promise((_resolve, reject) => {
    if (!signal) return // never resolves
    if (signal.aborted) {
      reject(new DOMException('The operation was aborted.', 'AbortError'))
      return
    }
    signal.addEventListener('abort', () => {
      reject(new DOMException('The operation was aborted.', 'AbortError'))
    })
  })
}

describe('ApiClient default timeout', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('passes a signal to every fetch call', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response(JSON.stringify({}), { status: 200 }))

    await rawApi.get('/test')

    expect(fetchSpy).toHaveBeenCalledOnce()
    const [, init] = fetchSpy.mock.calls[0]
    expect(init?.signal).toBeInstanceOf(AbortSignal)
  })

  it('applies the default timeout to POST requests', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response(JSON.stringify({}), { status: 200 }))

    await rawApi.post('/test', { key: 'value' })

    const [, init] = fetchSpy.mock.calls[0]
    expect(init?.signal).toBeInstanceOf(AbortSignal)
  })

  it('applies the default timeout to PUT requests', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response(JSON.stringify({}), { status: 200 }))

    await rawApi.put('/test', { key: 'value' })

    const [, init] = fetchSpy.mock.calls[0]
    expect(init?.signal).toBeInstanceOf(AbortSignal)
  })

  it('applies the default timeout to DELETE requests', async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response(JSON.stringify({}), { status: 200 }))

    await rawApi.delete('/test')

    const [, init] = fetchSpy.mock.calls[0]
    expect(init?.signal).toBeInstanceOf(AbortSignal)
  })

  it('rejects with AbortError when a pre-aborted caller signal is supplied', async () => {
    const controller = new AbortController()
    controller.abort()

    vi.spyOn(globalThis, 'fetch').mockImplementation((_url, init) =>
      hangingFetch(init?.signal as AbortSignal | undefined)
    )

    await expect(
      rawApi.get('/test', { signal: controller.signal })
    ).rejects.toMatchObject({
      name: 'AbortError',
    })
  })

  it('rejects with AbortError when the caller aborts mid-request', async () => {
    vi.spyOn(globalThis, 'fetch').mockImplementation((_url, init) =>
      hangingFetch(init?.signal as AbortSignal | undefined)
    )

    const controller = new AbortController()
    const promise = rawApi.get('/slow', { signal: controller.signal })

    // Abort via the caller controller after the fetch has started
    controller.abort()

    await expect(promise).rejects.toMatchObject({ name: 'AbortError' })
  })
})
