import type { FullConfig } from '@playwright/test'

const API_BASE = 'http://localhost:9293'

async function globalSetup(_config: FullConfig) {
  const response = await fetch(`${API_BASE}/api/test/reset`, {
    method: 'POST',
  })
  if (!response.ok) {
    throw new Error(`Failed to reset test database: ${response.status}`)
  }
}

export default globalSetup
