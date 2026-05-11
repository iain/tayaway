import { test, expect, APIRequestContext } from '@playwright/test'
import { createServer, type Server, type IncomingMessage } from 'node:https'
import type { AddressInfo } from 'node:net'
import { createECDH, randomBytes } from 'node:crypto'

interface SelfSignedCert {
  key: string
  cert: string
}

// Node 19+ ships X509Certificate.signWith but not a fully-formed CA helper,
// so reach for a tiny inline self-signer using openssl on PATH. The cert
// is regenerated per test run; the e2e backend disables peer verification
// (see config/environment.rb) so the cert just needs to make TLS handshake
// work, not be trusted.
import { execFileSync } from 'node:child_process'
import { mkdtempSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

function generateSelfSignedCert(): SelfSignedCert {
  const dir = mkdtempSync(join(tmpdir(), 'push-smoke-'))
  try {
    execFileSync(
      'openssl',
      [
        'req',
        '-x509',
        '-newkey',
        'rsa:2048',
        '-keyout',
        join(dir, 'key.pem'),
        '-out',
        join(dir, 'cert.pem'),
        '-days',
        '1',
        '-nodes',
        '-subj',
        '/CN=localhost',
      ],
      { stdio: 'pipe' }
    )
    return {
      key: readFileSync(join(dir, 'key.pem'), 'utf8'),
      cert: readFileSync(join(dir, 'cert.pem'), 'utf8'),
    }
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
}
import {
  API_BASE,
  PAGE_LOAD_TIMEOUT,
  getTestSession,
  setupAuthenticatedPage,
  newApiContext,
} from '../helpers'

const TEST_EMAIL = 'e2e-push@example.com'
const TEST_NAME = 'E2E Push User'

interface CapturedRequest {
  url: string
  method: string
  headers: Record<string, string | string[] | undefined>
  body: Buffer
}

function bufferToBase64(buffer: Buffer): string {
  return buffer.toString('base64')
}

function generateBrowserKeys(): { p256dhBase64: string; authBase64: string } {
  // The webpush gem decodes p256dh from base64 and treats it as a real
  // P-256 public point — a random 65-byte buffer would fail
  // `EC_POINT_bn2point`. Generate a real ECDH key pair so the encrypt
  // path inside the gem actually works.
  const ecdh = createECDH('prime256v1')
  ecdh.generateKeys()
  return {
    p256dhBase64: bufferToBase64(ecdh.getPublicKey()),
    authBase64: bufferToBase64(randomBytes(16)),
  }
}

// Stubs `navigator.serviceWorker.ready` and the push manager so the page
// can complete a subscribe round-trip without contacting a real push
// service, and pins `Notification.permission === 'granted'` so the
// composable doesn't disable the Enable button on construction.
function installPushManagerStub(
  endpoint: string,
  keys: { p256dhBase64: string; authBase64: string }
): string {
  return `
    Object.defineProperty(window.Notification, 'permission', {
      configurable: true,
      get: () => 'granted',
    })
    window.Notification.requestPermission = () => Promise.resolve('granted')

    const decodeBase64 = (b64) => {
      const raw = atob(b64)
      const out = new Uint8Array(raw.length)
      for (let i = 0; i < raw.length; i += 1) out[i] = raw.charCodeAt(i)
      return out
    }
    const p256dhKey = decodeBase64(${JSON.stringify(keys.p256dhBase64)})
    const authKey = decodeBase64(${JSON.stringify(keys.authBase64)})

    const fakeSubscription = {
      endpoint: ${JSON.stringify(endpoint)},
      getKey: (name) => (name === 'p256dh' ? p256dhKey.buffer : authKey.buffer),
      unsubscribe: () => Promise.resolve(true),
      toJSON: () => ({ endpoint: ${JSON.stringify(endpoint)} }),
    }

    let currentSubscription = null
    const fakeRegistration = {
      pushManager: {
        getSubscription: () => Promise.resolve(currentSubscription),
        subscribe: () => {
          currentSubscription = fakeSubscription
          return Promise.resolve(fakeSubscription)
        },
      },
      update: () => Promise.resolve(),
      unregister: () => Promise.resolve(true),
    }

    Object.defineProperty(navigator, 'serviceWorker', {
      configurable: true,
      value: {
        ready: Promise.resolve(fakeRegistration),
        register: () => Promise.resolve(fakeRegistration),
        getRegistration: () => Promise.resolve(fakeRegistration),
        addEventListener: () => {},
        removeEventListener: () => {},
        controller: null,
      },
    })
  `
}

test.describe('Push notifications opt-in', () => {
  let apiContext: APIRequestContext
  let token: string
  let pushServer: Server
  let pushPort: number
  let captured: CapturedRequest[]

  test.beforeAll(async ({ playwright }) => {
    apiContext = await newApiContext(playwright)
    const session = await getTestSession(apiContext, TEST_EMAIL, TEST_NAME)
    token = session.token

    captured = []
    const tls = generateSelfSignedCert()
    pushServer = createServer(
      { key: tls.key, cert: tls.cert },
      (req: IncomingMessage, res) => {
        const chunks: Buffer[] = []
        req.on('data', (chunk: Buffer) => chunks.push(chunk))
        req.on('end', () => {
          captured.push({
            url: req.url ?? '',
            method: req.method ?? '',
            headers: req.headers,
            body: Buffer.concat(chunks),
          })
          // The web-push gem expects 201 Created. Anything else triggers
          // retries / errors.
          res.statusCode = 201
          res.end()
        })
      }
    )
    await new Promise<void>((resolve) => pushServer.listen(0, resolve))
    pushPort = (pushServer.address() as AddressInfo).port
  })

  test.afterAll(async () => {
    await apiContext.dispose()
    await new Promise<void>((resolve) => pushServer.close(() => resolve()))
  })

  test('subscribes via the UI and delivers a push to the recorded endpoint', async ({
    page,
    context,
  }) => {
    await context.grantPermissions(['notifications'])
    const fakeEndpoint = `https://localhost:${pushPort}/push/${Math.random()
      .toString(36)
      .slice(2)}`
    const keys = generateBrowserKeys()
    await page.addInitScript(installPushManagerStub(fakeEndpoint, keys))
    await setupAuthenticatedPage(page, token)

    // 1. Subscribe via the UI — Enable button → POST /push-subscriptions →
    // page swaps to "Disable".
    const subscribeRequest = page.waitForRequest(
      (req) =>
        req.url().endsWith('/api/notifications/push-subscriptions') &&
        req.method() === 'POST'
    )

    await page.goto('/settings/notifications', { timeout: PAGE_LOAD_TIMEOUT })
    await page.getByRole('button', { name: /^Enable$/ }).click()

    const subscribeBody = (await subscribeRequest).postDataJSON() as {
      endpoint: string
    }
    expect(subscribeBody.endpoint).toBe(fakeEndpoint)
    await expect(page.getByRole('button', { name: /^Disable$/ })).toBeVisible()

    // 2. Drive the dispatcher → web-push → fake push server. Reset the
    // capture buffer first so we only see the push triggered by this call.
    captured.length = 0

    const triggerResponse = await apiContext.post(
      `${API_BASE}/api/test/dispatch-test-push`,
      {
        headers: { Cookie: `session_token=${token}` },
      }
    )
    if (!triggerResponse.ok()) {
      const text = await triggerResponse.text()
      throw new Error(
        `dispatch-test-push failed: ${triggerResponse.status()} ${text}`
      )
    }

    // 3. Wait for the fake push service to receive the encrypted payload.
    await expect
      .poll(() => captured.length, { timeout: 5_000 })
      .toBeGreaterThan(0)
    const delivery = captured[0]
    expect(delivery.method).toBe('POST')
    // VAPID-signed Web Push must include an Authorization header carrying
    // the JWT. Anything else means web-push didn't sign the request.
    expect(delivery.headers.authorization).toMatch(/vapid t=/i)
    // aes128gcm content-encoding is what web-push 3.x uses by default.
    expect(delivery.headers['content-encoding']).toBe('aes128gcm')
    expect(delivery.body.length).toBeGreaterThan(0)
  })
})
