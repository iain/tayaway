import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'

vi.mock('@/stores', () => ({
  useNotificationsStore: vi.fn(() => ({ showError: vi.fn() })),
  useObjectPoolStore: vi.fn(() => ({
    importObjects: vi.fn(),
    remove: vi.fn(),
  })),
}))

// Import after mocks are set up
const { api } = await import('./client')

function mockFetchResponse(
  status: number,
  body: unknown,
  ok: boolean = status >= 200 && status < 300
) {
  const jsonFn = vi.fn().mockResolvedValue(body)
  const response = { ok, status, statusText: String(status), json: jsonFn }
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue(response))
  return { jsonFn }
}

describe('ApiClient console logging', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.spyOn(console, 'error').mockImplementation(() => {})
  })

  afterEach(() => {
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
  })

  it('logs to console.error on HTTP error', async () => {
    mockFetchResponse(500, { error: 'Internal Server Error' }, false)

    await expect(api.get('/events')).rejects.toMatchObject({ status: 500 })

    expect(console.error).toHaveBeenCalledOnce()
    const call = vi.mocked(console.error).mock.calls[0]!
    expect(call[0]).toMatch(/GET/)
    expect(call[0]).toMatch(/\/api\/events/)
    expect(call[0]).toMatch(/500/)
  })

  it('includes the server error message in the console.error call', async () => {
    mockFetchResponse(404, { error: 'Not found' }, false)

    await expect(api.get('/events/missing')).rejects.toMatchObject({
      status: 404,
    })

    const call = vi.mocked(console.error).mock.calls[0]!
    expect(call[0]).toMatch(/Not found/)
  })

  it('logs to console.error when response JSON parse fails', async () => {
    const response = {
      ok: true,
      status: 200,
      statusText: '200',
      json: vi.fn().mockRejectedValue(new SyntaxError('Unexpected token')),
    }
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(response))

    await expect(api.get('/events')).rejects.toBeInstanceOf(SyntaxError)

    expect(console.error).toHaveBeenCalledOnce()
    const call = vi.mocked(console.error).mock.calls[0]!
    expect(call[0]).toMatch(/GET/)
    expect(call[0]).toMatch(/\/api\/events/)
    expect(call[0]).toMatch(/parse failed/)
  })

  it('does not log on successful request', async () => {
    mockFetchResponse(200, { objects: [] })

    await api.get('/events')

    expect(console.error).not.toHaveBeenCalled()
  })
})
