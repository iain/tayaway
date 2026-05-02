import { ref, computed } from 'vue'
import { defineStore } from 'pinia'
import { rawApi } from '@/api/client'
import { useCommandQueueStore } from './commandQueue'
import { useObjectPoolStore } from './objectPool'
import { useWebSocketStore } from './websocket'
import { useMutation } from '@/composables/useMutation'

import { teardownSession } from '@/api/teardownSession'
import { startRegistration, startAuthentication } from '@simplewebauthn/browser'
import type {
  AuthUser,
  LoginLinkResponse,
  VerifyResponse,
  MeResponse,
  LogoutResponse,
  EmailChangeRequestResponse,
  EmailChangeVerifyResponse,
  Passkey,
  PasskeysListResponse,
  PasskeyRegistrationBeginResponse,
  PasskeyAuthenticationBeginResponse,
  PasskeyRegistrationResponse,
  PasskeyDeleteResponse,
} from '@/types'
import type { PoolApiResponse } from '@/types/pool'

/** Mask an IBAN for display: "NL02 •••• •••• 5678" */
function maskIban(iban: string): string {
  if (iban.length <= 8) return iban
  const middle = Math.floor((iban.length - 8) / 4)
  return `${iban.slice(0, 4)} ${'•••• '.repeat(middle)}${iban.slice(-4)}`
}

const AUTH_USER_KEY = 'tayaway_auth_user'
const AUTH_USER_TTL_MS = 24 * 60 * 60 * 1000 // 24 hours

function cacheUser(u: AuthUser): void {
  // Omit iban before caching — sensitive data should not persist in localStorage
  const entry = {
    user: {
      id: u.id,
      email: u.email,
      name: u.name,
      phoneNumber: u.phoneNumber,
      birthday: u.birthday,
      locationName: u.locationName,
      latitude: u.latitude,
      longitude: u.longitude,
    },
    cachedAt: Date.now(),
  }
  localStorage.setItem(AUTH_USER_KEY, JSON.stringify(entry))
}

function getCachedUser(): AuthUser | null {
  try {
    const raw = localStorage.getItem(AUTH_USER_KEY)
    if (!raw) return null
    const parsed = JSON.parse(raw) as Record<string, unknown>
    // Support legacy format (no cachedAt) — treat as expired so stale sessions
    // are cleared on the next online boot
    const cachedAt =
      typeof parsed.cachedAt === 'number' ? parsed.cachedAt : null
    if (cachedAt === null || Date.now() - cachedAt > AUTH_USER_TTL_MS) {
      localStorage.removeItem(AUTH_USER_KEY)
      return null
    }
    return parsed.user as AuthUser
  } catch {
    return null
  }
}

function clearCachedUser(): void {
  localStorage.removeItem(AUTH_USER_KEY)
}

function mapMeResponseToAuthUser(data: MeResponse): AuthUser {
  return {
    id: data.user_id,
    email: data.email,
    name: data.name,
    phoneNumber: data.phoneNumber ?? null,
    birthday: data.birthday ?? null,
    locationName: data.locationName ?? null,
    latitude: data.latitude ?? null,
    longitude: data.longitude ?? null,
    iban: data.iban ?? null,
  }
}

export const useAuthStore = defineStore('auth', () => {
  const user = ref<AuthUser | null>(null)
  const loading = ref(false)
  const initialized = ref(false)

  const isAuthenticated = computed(() => user.value !== null)

  const currentUserId = computed(() => user.value?.id ?? null)

  /**
   * Fetch /api/auth/me with a 5s timeout and process the result.
   * Returns true if the session is valid, false if it is definitively invalid
   * (401/403), and null if the server was unreachable (network/timeout/5xx).
   */
  async function fetchMe(): Promise<boolean | null> {
    try {
      const response = await fetch('/api/auth/me', {
        signal: AbortSignal.timeout(5000),
      })

      if (response.ok) {
        const data = (await response.json()) as MeResponse
        user.value = mapMeResponseToAuthUser(data)
        cacheUser(user.value)
        return true
      } else if (response.status === 401 || response.status === 403) {
        return false
      } else {
        // Server unavailable (5xx) — treat as unreachable
        return null
      }
    } catch (e) {
      // Genuine network/abort errors are expected when offline or on slow
      // connections — fall back to cached user silently.
      // Any other error (programming bug, unexpected exception) should be
      // logged so it doesn't disappear unnoticed.
      const isNetworkError =
        e instanceof DOMException && e.name === 'AbortError'
          ? true
          : e instanceof TypeError &&
            /fetch|network|failed to fetch/i.test(e.message)
      if (!isNetworkError) {
        console.error('[auth] initialize() caught unexpected error:', e)
      }
      return null
    }
  }

  async function initialize(): Promise<void> {
    // If already initialized with a valid user, skip
    if (initialized.value && user.value) return

    const cached = getCachedUser()

    if (cached) {
      // Render immediately from cache — don't block navigation on the network.
      user.value = cached
      initialized.value = true

      // Validate the session in the background. If 401/403, redirect to login.
      validateInBackground()
      return
    }

    // No cache — block until the network responds so we know whether to render
    // protected content or redirect to login.
    try {
      loading.value = true
      const valid = await fetchMe()

      if (valid === true) {
        // fetchMe() already set user.value and cached the user
        const ws = useWebSocketStore()
        ws.connect()
      } else if (valid === false) {
        // Session truly invalid — clear cache and require re-login
        user.value = null
        clearCachedUser()
      } else {
        // Server unreachable — no cached user, treat as logged out
        user.value = null
      }
    } finally {
      loading.value = false
      initialized.value = true
    }
  }

  /**
   * Re-validate the cached session against /api/auth/me in the background.
   * Called after a cache-hit in initialize() so the UI renders immediately
   * while we confirm the session is still live.
   *
   * - 200: refresh user data and connect WebSocket
   * - 401/403: clear state and redirect to /login
   * - Network error / 5xx: keep the cached state, connect WebSocket optimistically
   */
  function validateInBackground(): void {
    // Connect WebSocket optimistically — the server will reject the ticket
    // if the session is invalid, at which point we'll redirect.
    const ws = useWebSocketStore()
    ws.connect()

    fetchMe()
      .then(async (valid) => {
        if (valid === true) {
          // Session confirmed — WebSocket already connected, nothing else to do
        } else if (valid === false) {
          // Session expired — full cleanup and redirect to login
          const { handleSessionExpired } = await import('@/api/sessionExpired')
          await handleSessionExpired()
        }
        // null (network error / 5xx): keep cached state, stay connected
      })
      .catch((e: unknown) => {
        // Unexpected error in the background validator — log but don't crash
        console.error(
          '[auth] validateInBackground() caught unexpected error:',
          e
        )
      })
  }

  async function requestLoginLink(email: string): Promise<string> {
    const response = await rawApi.post<LoginLinkResponse>('/auth/login-link', {
      email,
    })
    return response.data.message
  }

  async function completeLogin(): Promise<AuthUser> {
    const meResponse = await rawApi.get<MeResponse>('/auth/me')
    const verifiedUser = mapMeResponseToAuthUser(meResponse.data)
    user.value = verifiedUser
    cacheUser(verifiedUser)

    const ws = useWebSocketStore()
    ws.connect()

    const commandQueue = useCommandQueueStore()
    if (commandQueue.pendingCount > 0) {
      commandQueue.processQueue()
    }

    return verifiedUser
  }

  async function verifyToken(token: string): Promise<AuthUser> {
    await rawApi.post<VerifyResponse>('/auth/verify', { token })
    return completeLogin()
  }

  async function logout(): Promise<void> {
    try {
      await rawApi.post<LogoutResponse>('/auth/logout')
    } finally {
      user.value = null
      await teardownSession()
    }
  }

  interface ProfileFields {
    name?: string
    phoneNumber?: string | null
    birthday?: string | null
    locationName?: string | null
    latitude?: number | null
    longitude?: number | null
    iban?: string | null
  }

  async function updateProfile(fields: ProfileFields): Promise<void> {
    if (!user.value) return
    const previousUser = { ...user.value }
    const userId = user.value.id
    const pool = useObjectPoolStore()
    const member = pool.findBy('member', 'userId', userId)
    const { mutate, update } = useMutation()

    // Optimistically update the auth ref. The API treats "" as "clear this
    // field" (and null/undefined as "no change"), but the local state should
    // surface a cleared field as null so display fallbacks like "Not set" fire.
    const blankToNull = (v: string | null | undefined) =>
      v === '' ? null : (v ?? null)
    if (fields.name !== undefined) user.value.name = fields.name
    if (fields.phoneNumber !== undefined)
      user.value.phoneNumber = blankToNull(fields.phoneNumber)
    if (fields.birthday !== undefined)
      user.value.birthday = blankToNull(fields.birthday)
    if (fields.locationName !== undefined)
      user.value.locationName = blankToNull(fields.locationName)
    if (fields.latitude !== undefined) user.value.latitude = fields.latitude
    if (fields.longitude !== undefined) user.value.longitude = fields.longitude
    if (fields.iban !== undefined)
      user.value.iban = fields.iban ? maskIban(fields.iban) : null

    try {
      const apiCall = (commandQueue: ReturnType<typeof useCommandQueueStore>) =>
        commandQueue.enqueue<PoolApiResponse>('PUT', `/users/${userId}`, fields)

      // Build optimistic pool changes from provided fields. Same blank → null
      // normalization as above so the pool-driven UI matches the cleared state.
      const poolChanges: Record<string, unknown> = {}
      if (fields.name !== undefined) poolChanges.name = fields.name
      if (fields.phoneNumber !== undefined)
        poolChanges.phoneNumber = blankToNull(fields.phoneNumber)
      if (fields.birthday !== undefined)
        poolChanges.birthday = blankToNull(fields.birthday)
      if (fields.locationName !== undefined)
        poolChanges.locationName = blankToNull(fields.locationName)
      if (fields.latitude !== undefined) poolChanges.latitude = fields.latitude
      if (fields.longitude !== undefined)
        poolChanges.longitude = fields.longitude
      const result = member
        ? await update(
            'Failed to update profile',
            'member',
            member.id,
            poolChanges,
            apiCall
          )
        : await mutate('Failed to update profile', apiCall)

      if (!result.queued && user.value) {
        const poolMember = member ? pool.get('member', member.id) : null
        if (poolMember) {
          user.value.name = poolMember.name
          user.value.phoneNumber = poolMember.phoneNumber
          user.value.birthday = poolMember.birthday
          user.value.locationName = poolMember.locationName
          user.value.latitude = poolMember.latitude
          user.value.longitude = poolMember.longitude
        }
      }
      if (user.value) cacheUser(user.value)
    } catch (e) {
      // Restore previous state on failure
      if (user.value) Object.assign(user.value, previousUser)
      throw e
    }
  }

  async function updateName(name: string): Promise<void> {
    return updateProfile({ name })
  }

  async function requestEmailChange(email: string): Promise<string> {
    const response = await rawApi.post<EmailChangeRequestResponse>(
      '/users/email-change/request',
      { email }
    )
    return response.data.message
  }

  async function verifyEmailChange(token: string): Promise<string> {
    const response = await rawApi.post<EmailChangeVerifyResponse>(
      '/users/email-change/verify',
      { token }
    )

    // If authenticated, refresh user info
    if (user.value) {
      try {
        const meResponse = await rawApi.get<MeResponse>('/auth/me')
        user.value = mapMeResponseToAuthUser(meResponse.data)
        cacheUser(user.value)
      } catch {
        // May not be authenticated (different browser) — that's fine
      }
    }

    return response.data.message
  }

  // --- Passkey methods ---

  async function listPasskeys(): Promise<Passkey[]> {
    const { data } = await rawApi.get<PasskeysListResponse>('/auth/passkeys')
    return data.passkeys
  }

  async function registerPasskey(name?: string): Promise<Passkey> {
    const { data: beginData } =
      await rawApi.post<PasskeyRegistrationBeginResponse>(
        '/auth/passkeys/register/begin'
      )

    const credential = await startRegistration({
      optionsJSON: beginData.options,
    })

    const { data } = await rawApi.post<PasskeyRegistrationResponse>(
      '/auth/passkeys/register/complete',
      {
        challengeToken: beginData.challengeToken,
        credential: credential,
        name,
      }
    )

    return data.passkey
  }

  async function authenticateWithPasskey(options?: {
    mediation?: CredentialMediationRequirement
    signal?: AbortSignal
  }): Promise<AuthUser> {
    const { data: beginData } =
      await rawApi.post<PasskeyAuthenticationBeginResponse>(
        '/auth/passkeys/authenticate/begin',
        undefined,
        { silent: true, signal: options?.signal }
      )

    const credential = await startAuthentication({
      optionsJSON: beginData.options,
      useBrowserAutofill: options?.mediation === 'conditional',
    })

    // If aborted between begin and complete, bail out
    options?.signal?.throwIfAborted()

    await rawApi.post(
      '/auth/passkeys/authenticate/complete',
      {
        challengeToken: beginData.challengeToken,
        credential: credential,
      },
      { silent: true }
    )

    // Session cookie is now set — complete the login flow
    return completeLogin()
  }

  async function renamePasskey(id: string, name: string): Promise<Passkey> {
    const { data } = await rawApi.put<{ passkey: Passkey }>(
      `/auth/passkeys/${id}`,
      { name }
    )
    return data.passkey
  }

  async function deletePasskey(id: string): Promise<void> {
    await rawApi.delete<PasskeyDeleteResponse>(`/auth/passkeys/${id}`)
  }

  function $reset() {
    clearCachedUser()
    user.value = null
    loading.value = false
    initialized.value = false
  }

  return {
    user,
    loading,
    initialized,
    isAuthenticated,
    currentUserId,
    initialize,
    requestLoginLink,
    verifyToken,
    logout,
    updateProfile,
    updateName,
    requestEmailChange,
    verifyEmailChange,
    listPasskeys,
    registerPasskey,
    authenticateWithPasskey,
    renamePasskey,
    deletePasskey,
    $reset,
  }
})
