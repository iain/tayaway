import type { FullConfig } from '@playwright/test'

const API_BASE = 'http://localhost:9293'
const MAX_ATTEMPTS = 5

async function globalSetup(_config: FullConfig) {
  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    let response
    try {
      response = await fetch(`${API_BASE}/api/test/reset`, {
        method: 'POST',
      })
    } catch {
      if (attempt < MAX_ATTEMPTS - 1) {
        const delay = 200 * Math.pow(2, attempt) + Math.random() * 100
        await new Promise((r) => setTimeout(r, delay))
        continue
      }
      throw new Error('Failed to reset test database: connection refused')
    }
    if (response.ok) return
    if (response.status >= 500 && attempt < MAX_ATTEMPTS - 1) {
      const delay = 200 * Math.pow(2, attempt) + Math.random() * 100
      await new Promise((r) => setTimeout(r, delay))
      continue
    }
    throw new Error(`Failed to reset test database: ${response.status}`)
  }
}

export default globalSetup
