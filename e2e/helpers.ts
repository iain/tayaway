import { Page, APIRequestContext } from '@playwright/test'

export const API_BASE = 'http://localhost:9293'

// Creates an API request context with the CSRF header required by the backend
// for all state-changing requests (POST/PUT/PATCH/DELETE).
export async function newApiContext(
  playwright: { request: { newContext: (options?: object) => Promise<APIRequestContext> } },
  options?: Record<string, unknown>
): Promise<APIRequestContext> {
  const { extraHTTPHeaders, ...rest } = options ?? {}
  return playwright.request.newContext({
    extraHTTPHeaders: {
      'X-CSRF-Protection': '1',
      ...((extraHTTPHeaders as Record<string, string>) ?? {}),
    },
    ...rest,
  })
}

// Assertions that fire immediately after page.goto() need extra headroom for
// the frontend to fetch data and render. Everything else uses the 5 s default
// configured in playwright.config.ts.
export const PAGE_LOAD_TIMEOUT = 10_000

export interface PoolObject {
  id: string
  objectType: string
  [key: string]: unknown
}

export function getObjectByType<T extends PoolObject>(
  objects: PoolObject[],
  type: string
): T | undefined {
  return objects.find((o) => o.objectType === type) as T | undefined
}

export function getObjectsByType<T extends PoolObject>(
  objects: PoolObject[],
  type: string
): T[] {
  return objects.filter((o) => o.objectType === type) as T[]
}

const MAX_SESSION_ATTEMPTS = 8
const MAX_SESSION_DELAY = 3000

export async function getTestSession(
  request: APIRequestContext,
  email: string,
  name: string
): Promise<{ token: string; userId: string }> {
  for (let attempt = 0; attempt < MAX_SESSION_ATTEMPTS; attempt++) {
    let response
    try {
      response = await request.post(`${API_BASE}/api/test/session`, {
        data: { email, name },
      })
    } catch {
      // Connection error (ECONNREFUSED, etc.) — retry with backoff
      if (attempt < MAX_SESSION_ATTEMPTS - 1) {
        const delay =
          Math.min(200 * Math.pow(2, attempt), MAX_SESSION_DELAY) +
          Math.random() * 100
        await new Promise((r) => setTimeout(r, delay))
        continue
      }
      throw new Error('Failed to create test session: connection refused')
    }
    if (response.ok()) {
      const body = await response.json()
      return { token: body.session_token, userId: body.user_id }
    }
    if (response.status() >= 500 && attempt < MAX_SESSION_ATTEMPTS - 1) {
      // Exponential backoff with jitter, capped to avoid long waits
      const delay =
        Math.min(200 * Math.pow(2, attempt), MAX_SESSION_DELAY) +
        Math.random() * 100
      await new Promise((r) => setTimeout(r, delay))
      continue
    }
    throw new Error(`Failed to create test session: ${response.status()}`)
  }
  throw new Error('Failed to create test session after retries')
}

export async function setupAuthenticatedPage(
  page: Page,
  token: string
): Promise<void> {
  await page.context().addCookies([
    {
      name: 'session_token',
      value: token,
      domain: 'localhost',
      path: '/',
      httpOnly: true,
      sameSite: 'Lax',
    },
  ])
}

export async function createBareEvent(
  request: APIRequestContext,
  name = 'Test Event'
): Promise<string> {
  const response = await request.post(`${API_BASE}/api/events`, {
    data: { name, description: 'Test event' },
  })
  const body = await response.json()
  const event = getObjectByType(body.objects, 'event')
  return event!.id
}

export async function createEventWithPoll(
  request: APIRequestContext,
  name = 'Test Event'
): Promise<{
  eventId: string
  dateRangeIds: string[]
  dateRangeId: string
  workspaceId: string
}> {
  const eventResponse = await request.post(`${API_BASE}/api/events`, {
    data: { name, description: 'Test event with poll' },
  })
  const eventBody = await eventResponse.json()
  const event = getObjectByType(eventBody.objects, 'event')
  const eventId = event!.id

  const deadline = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString()
  await request.post(`${API_BASE}/api/events/${eventId}/poll`, {
    data: { deadline },
  })

  const [dr1Response, dr2Response] = await Promise.all([
    request.post(`${API_BASE}/api/events/${eventId}/poll/date-ranges`, {
      data: { start_date: '2026-06-01', end_date: '2026-06-07' },
    }),
    request.post(`${API_BASE}/api/events/${eventId}/poll/date-ranges`, {
      data: { start_date: '2026-06-15', end_date: '2026-06-20' },
    }),
  ])
  const [dr1Body, dr2Body] = await Promise.all([
    dr1Response.json(),
    dr2Response.json(),
  ])
  const dr1 = getObjectByType(dr1Body.objects, 'dateRange')
  const dr2 = getObjectByType(dr2Body.objects, 'dateRange')

  return {
    eventId,
    dateRangeIds: [dr1!.id, dr2!.id],
    dateRangeId: dr1!.id,
    workspaceId: event!.workspaceId as string,
  }
}

export async function getWorkspaceId(
  request: APIRequestContext
): Promise<string> {
  const response = await request.get(`${API_BASE}/api/workspaces`)
  const body = await response.json()
  const workspace = getObjectByType(body.objects, 'workspace')
  if (!workspace) throw new Error('No workspace found for this user')
  return workspace.id
}

export async function createTaskList(
  request: APIRequestContext,
  workspaceId: string,
  name = 'Test List'
): Promise<string> {
  const response = await request.post(`${API_BASE}/api/task-lists`, {
    data: { workspace_id: workspaceId, name },
  })
  const body = await response.json()
  const taskList = getObjectByType(body.objects, 'taskList')
  return taskList!.id
}

export async function addTaskItem(
  request: APIRequestContext,
  taskListId: string,
  content = 'Test item'
): Promise<string> {
  const response = await request.post(
    `${API_BASE}/api/task-lists/${taskListId}/items`,
    { data: { content } }
  )
  const body = await response.json()
  // AddItem returns the full task list with all items; find the specific one by content
  const items = getObjectsByType(body.objects, 'taskItem')
  const item = items.find((i) => (i as { content: string }).content === content)
  return item!.id
}

export async function addMemberToWorkspace(
  request: APIRequestContext,
  workspaceId: string,
  email: string
): Promise<string> {
  const response = await request.post(`${API_BASE}/api/test/add-member`, {
    data: { workspace_id: workspaceId, email },
  })
  const body = await response.json()
  return body.member_id
}

export async function createResolvedEvent(
  request: APIRequestContext,
  name = 'Test Event'
): Promise<{ eventId: string; winnerDateRangeId: string }> {
  const { eventId, dateRangeIds } = await createEventWithPoll(request, name)

  await request.post(`${API_BASE}/api/events/${eventId}/votes`, {
    data: { date_range_id: dateRangeIds[0], response: 'yes' },
  })

  await request.post(`${API_BASE}/api/events/${eventId}/poll/close`, {
    data: { selected_date_range_id: dateRangeIds[0] },
  })

  return { eventId, winnerDateRangeId: dateRangeIds[0] }
}
