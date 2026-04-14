import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'

const mockStopPersisting = vi.fn()
vi.mock('@/api/poolPersistence', () => ({
  poolPersistence: {
    loadFromCache: vi.fn(),
    startPersisting: vi.fn(),
    stopPersisting: mockStopPersisting,
  },
}))

vi.mock('./commandQueue', () => ({
  useCommandQueueStore: vi.fn(() => ({
    enqueue: vi.fn(),
    reset: vi.fn(),
    pendingCount: 0,
    processQueue: vi.fn(),
  })),
}))

vi.mock('./objectPool', () => ({
  useObjectPoolStore: vi.fn(() => ({
    importObjects: vi.fn(),
    remove: vi.fn(),
    findBy: vi.fn(),
    get: vi.fn(),
    $reset: vi.fn(),
  })),
}))

vi.mock('./websocket', () => ({
  useWebSocketStore: vi.fn(() => ({
    connect: vi.fn(),
    disconnect: vi.fn(),
  })),
}))

vi.mock('./workspace', () => ({
  useWorkspaceStore: vi.fn(() => ({
    $reset: vi.fn(),
  })),
}))

vi.mock('@/api/poolDb', () => ({
  clearAll: vi.fn(),
}))

vi.mock('@/composables/useMutation', () => ({
  useMutation: vi.fn(() => ({
    mutate: vi.fn(),
    update: vi.fn(),
  })),
}))

vi.mock('@simplewebauthn/browser', () => ({
  startRegistration: vi.fn(),
  startAuthentication: vi.fn(),
}))

function jsonResponse(data: unknown, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => data,
  } as Response
}

describe('auth store – passkey methods', () => {
  beforeEach(() => {
    vi.resetModules()
    setActivePinia(createPinia())
    vi.stubGlobal('fetch', vi.fn())
    localStorage.clear()
  })

  afterEach(() => {
    vi.unstubAllGlobals()
  })

  describe('listPasskeys()', () => {
    it('returns passkeys from the API', async () => {
      const passkeys = [
        {
          id: 'pk-1',
          name: 'MacBook',
          aaguid: null,
          createdAt: '2026-01-01T00:00:00Z',
        },
        {
          id: 'pk-2',
          name: 'YubiKey',
          aaguid: null,
          createdAt: '2026-01-02T00:00:00Z',
        },
      ]
      vi.mocked(fetch).mockResolvedValue(jsonResponse({ passkeys }))

      const { useAuthStore } = await import('./auth')
      const store = useAuthStore()
      const result = await store.listPasskeys()

      expect(result).toEqual(passkeys)
      expect(fetch).toHaveBeenCalledWith(
        '/api/auth/passkeys',
        expect.objectContaining({ method: 'GET' })
      )
    })
  })

  describe('registerPasskey()', () => {
    it('calls begin, runs WebAuthn ceremony, then calls complete', async () => {
      const beginResponse = {
        options: {
          challenge: 'test-challenge',
          rp: {},
          user: {},
          pubKeyCredParams: [],
        },
        challengeToken: 'jwt-token',
      }
      const passkey = {
        id: 'pk-1',
        name: 'My Key',
        aaguid: null,
        createdAt: '2026-01-01T00:00:00Z',
      }
      const fakeCredential = { id: 'cred-id', response: {} }

      vi.mocked(fetch)
        .mockResolvedValueOnce(jsonResponse(beginResponse)) // register/begin
        .mockResolvedValueOnce(jsonResponse({ passkey })) // register/complete

      const { startRegistration } = await import('@simplewebauthn/browser')
      vi.mocked(startRegistration).mockResolvedValue(fakeCredential as never)

      const { useAuthStore } = await import('./auth')
      const store = useAuthStore()
      const result = await store.registerPasskey('My Key')

      expect(result).toEqual(passkey)
      expect(startRegistration).toHaveBeenCalledWith({
        optionsJSON: beginResponse.options,
      })
      expect(fetch).toHaveBeenCalledTimes(2)
    })
  })

  describe('authenticateWithPasskey()', () => {
    it('calls begin, runs WebAuthn ceremony, calls complete, then fetches /me', async () => {
      const beginResponse = {
        options: { challenge: 'auth-challenge', rpId: 'localhost' },
        challengeToken: 'jwt-auth-token',
      }
      const meResponse = {
        user_id: 'user-1',
        email: 'user@example.com',
        name: 'Test',
        phoneNumber: null,
        birthday: null,
        locationName: null,
        latitude: null,
        longitude: null,
        iban: null,
      }
      const fakeAssertion = { id: 'cred-id', response: {} }

      vi.mocked(fetch)
        .mockResolvedValueOnce(jsonResponse(beginResponse)) // authenticate/begin
        .mockResolvedValueOnce(
          jsonResponse({ user_id: 'user-1', session_token: 'tok' })
        ) // authenticate/complete
        .mockResolvedValueOnce(jsonResponse(meResponse)) // /me

      const { startAuthentication } = await import('@simplewebauthn/browser')
      vi.mocked(startAuthentication).mockResolvedValue(fakeAssertion as never)

      const { useAuthStore } = await import('./auth')
      const store = useAuthStore()
      const user = await store.authenticateWithPasskey()

      expect(user.id).toBe('user-1')
      expect(user.email).toBe('user@example.com')
      expect(store.user).toMatchObject({ id: 'user-1' })
      expect(startAuthentication).toHaveBeenCalledWith({
        optionsJSON: beginResponse.options,
        useBrowserAutofill: false,
      })
    })

    it('uses browser autofill when mediation is conditional', async () => {
      const beginResponse = {
        options: { challenge: 'c', rpId: 'localhost' },
        challengeToken: 'jwt',
      }
      const meResponse = {
        user_id: 'u1',
        email: 'a@b.com',
        name: null,
        phoneNumber: null,
        birthday: null,
        locationName: null,
        latitude: null,
        longitude: null,
        iban: null,
      }

      vi.mocked(fetch)
        .mockResolvedValueOnce(jsonResponse(beginResponse))
        .mockResolvedValueOnce(jsonResponse({ user_id: 'u1' }))
        .mockResolvedValueOnce(jsonResponse(meResponse))

      const { startAuthentication } = await import('@simplewebauthn/browser')
      vi.mocked(startAuthentication).mockResolvedValue({
        id: 'x',
        response: {},
      } as never)

      const { useAuthStore } = await import('./auth')
      const store = useAuthStore()
      await store.authenticateWithPasskey({ mediation: 'conditional' })

      expect(startAuthentication).toHaveBeenCalledWith(
        expect.objectContaining({ useBrowserAutofill: true })
      )
    })
  })

  describe('registerPasskey() — error paths', () => {
    it('propagates error when begin endpoint fails', async () => {
      vi.mocked(fetch).mockResolvedValueOnce(
        jsonResponse({ error: 'fail' }, 500)
      )

      const { useAuthStore } = await import('./auth')
      const store = useAuthStore()

      await expect(store.registerPasskey()).rejects.toThrow()
    })

    it('propagates error when startRegistration throws', async () => {
      const beginResponse = {
        options: { challenge: 'c', rp: {}, user: {}, pubKeyCredParams: [] },
        challengeToken: 'jwt',
      }
      vi.mocked(fetch).mockResolvedValueOnce(jsonResponse(beginResponse))

      const { startRegistration } = await import('@simplewebauthn/browser')
      const notAllowed = new Error('not allowed')
      notAllowed.name = 'NotAllowedError'
      vi.mocked(startRegistration).mockRejectedValue(notAllowed)

      const { useAuthStore } = await import('./auth')
      const store = useAuthStore()

      await expect(store.registerPasskey()).rejects.toThrow()
    })
  })

  describe('authenticateWithPasskey() — error paths', () => {
    it('propagates error when begin endpoint fails', async () => {
      vi.mocked(fetch).mockResolvedValueOnce(
        jsonResponse({ error: 'fail' }, 500)
      )

      const { useAuthStore } = await import('./auth')
      const store = useAuthStore()

      await expect(store.authenticateWithPasskey()).rejects.toThrow()
    })
  })

  describe('deletePasskey()', () => {
    it('calls DELETE on the passkey endpoint', async () => {
      vi.mocked(fetch).mockResolvedValue(
        jsonResponse({ message: 'Passkey deleted' })
      )

      const { useAuthStore } = await import('./auth')
      const store = useAuthStore()
      await store.deletePasskey('pk-1')

      expect(fetch).toHaveBeenCalledWith(
        '/api/auth/passkeys/pk-1',
        expect.objectContaining({ method: 'DELETE' })
      )
    })

    it('throws when the DELETE endpoint fails', async () => {
      vi.mocked(fetch).mockResolvedValue(
        jsonResponse({ error: 'Not found' }, 404)
      )

      const { useAuthStore } = await import('./auth')
      const store = useAuthStore()

      await expect(store.deletePasskey('pk-missing')).rejects.toThrow()
    })
  })

  describe('renamePasskey()', () => {
    it('calls PUT and returns updated passkey', async () => {
      const updated = {
        id: 'pk-1',
        name: 'New Name',
        aaguid: null,
        createdAt: '2026-01-01T00:00:00Z',
      }
      vi.mocked(fetch).mockResolvedValue(jsonResponse({ passkey: updated }))

      const { useAuthStore } = await import('./auth')
      const store = useAuthStore()
      const result = await store.renamePasskey('pk-1', 'New Name')

      expect(result).toEqual(updated)
      expect(fetch).toHaveBeenCalledWith(
        '/api/auth/passkeys/pk-1',
        expect.objectContaining({ method: 'PUT' })
      )
    })
  })
})
