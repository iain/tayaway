import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { Scope } from './scope'

const mockHandleSessionExpired = vi.fn()
vi.mock('@/api/sessionExpired', () => ({
  handleSessionExpired: mockHandleSessionExpired,
}))

vi.mock('@/stores', () => ({
  useNotificationsStore: vi.fn(() => ({ showError: vi.fn() })),
  useObjectPoolStore: vi.fn(() => ({
    importObjects: vi.fn(),
    remove: vi.fn(),
  })),
}))

const workspaceStore = { currentWorkspaceId: null as string | null }
vi.mock('@/stores/workspace', () => ({
  useWorkspaceStore: vi.fn(() => workspaceStore),
  WORKSPACE_ID_STORAGE_KEY: 'tayaway:workspaceId',
}))

const mockProcessPoolResponse = vi.fn()
vi.mock('@/api/processPoolResponse', () => ({
  processPoolResponse: mockProcessPoolResponse,
}))

// Import after mocks are set up. Tests exercise the raw client for the
// request/401/error logic and the pool-aware `api.get` for scope snapshotting.
const { rawApi, api } = await import('./client')

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

    await expect(rawApi.get('/events')).rejects.toMatchObject({ status: 500 })

    expect(console.error).toHaveBeenCalledOnce()
    const call = vi.mocked(console.error).mock.calls[0]!
    expect(call[0]).toMatch(/GET/)
    expect(call[0]).toMatch(/\/api\/events/)
    expect(call[0]).toMatch(/500/)
  })

  it('includes the server error message in the console.error call', async () => {
    mockFetchResponse(404, { error: 'Not found' }, false)

    await expect(rawApi.get('/events/missing')).rejects.toMatchObject({
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

    await expect(rawApi.get('/events')).rejects.toBeInstanceOf(SyntaxError)

    expect(console.error).toHaveBeenCalledOnce()
    const call = vi.mocked(console.error).mock.calls[0]!
    expect(call[0]).toMatch(/GET/)
    expect(call[0]).toMatch(/\/api\/events/)
    expect(call[0]).toMatch(/parse failed/)
  })

  it('does not log on successful request', async () => {
    mockFetchResponse(200, { objects: [] })

    await rawApi.get('/events')

    expect(console.error).not.toHaveBeenCalled()
  })
})

describe('ApiClient 401 interceptor', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.spyOn(console, 'error').mockImplementation(() => {})
    mockHandleSessionExpired.mockReset()
  })

  afterEach(() => {
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
  })

  it('calls handleSessionExpired on 401 from regular endpoints', async () => {
    mockFetchResponse(401, { error: 'Unauthorized' }, false)

    await expect(rawApi.get('/events')).rejects.toMatchObject({ status: 401 })
    expect(mockHandleSessionExpired).toHaveBeenCalledOnce()
  })

  it.each(['/auth/login-link', '/auth/verify', '/auth/me'])(
    'does not call handleSessionExpired on 401 from %s',
    async (path) => {
      mockFetchResponse(401, { error: 'Unauthorized' }, false)

      await expect(rawApi.post(path, {})).rejects.toMatchObject({ status: 401 })
      expect(mockHandleSessionExpired).not.toHaveBeenCalled()
    }
  )

  it('calls handleSessionExpired on 401 from /auth/ws-ticket', async () => {
    mockFetchResponse(401, { error: 'Unauthorized' }, false)

    await expect(rawApi.post('/auth/ws-ticket')).rejects.toMatchObject({
      status: 401,
    })
    expect(mockHandleSessionExpired).toHaveBeenCalledOnce()
  })

  it('does not call handleSessionExpired on non-401 errors', async () => {
    mockFetchResponse(403, { error: 'Forbidden' }, false)

    await expect(rawApi.get('/events')).rejects.toMatchObject({ status: 403 })
    expect(mockHandleSessionExpired).not.toHaveBeenCalled()
  })
})

describe('api.get workspace-scope snapshot', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    mockProcessPoolResponse.mockReset()
    workspaceStore.currentWorkspaceId = null
  })

  afterEach(() => {
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
  })

  it('tags the response with the workspace that was active at request time, not at response time', async () => {
    workspaceStore.currentWorkspaceId = 'ws-A'

    let resolveFetch: (value: unknown) => void = () => {}
    const fetchPromise = new Promise((resolve) => {
      resolveFetch = resolve
    })
    vi.stubGlobal('fetch', vi.fn().mockReturnValue(fetchPromise))

    const inFlight = api.get('/events')
    workspaceStore.currentWorkspaceId = 'ws-B'

    resolveFetch({
      ok: true,
      status: 200,
      statusText: '200',
      json: vi.fn().mockResolvedValue({ objects: [] }),
    })
    await inFlight

    expect(mockProcessPoolResponse).toHaveBeenCalledOnce()
    expect(mockProcessPoolResponse.mock.calls[0]![1]).toBe(Scope.workspace('ws-A'))
  })

  it('passes undefined scope when no workspace is active', async () => {
    workspaceStore.currentWorkspaceId = null
    mockFetchResponse(200, { objects: [] })

    await api.get('/events')

    expect(mockProcessPoolResponse).toHaveBeenCalledOnce()
    expect(mockProcessPoolResponse.mock.calls[0]![1]).toBeUndefined()
  })
})
