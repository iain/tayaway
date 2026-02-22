import { test, expect, APIRequestContext } from '@playwright/test'
import {
  API_BASE,
  getObjectByType,
  getObjectsByType,
  getTestSession,
  setupAuthenticatedPage,
  getWorkspaceId,
  createTaskList,
  addTaskItem,
} from '../helpers'

const TEST_EMAIL = 'e2e-tasks@example.com'
const TEST_NAME = 'E2E Tasks User'

test.describe('Tasks Feature', () => {
  test.describe('Task Lists API - Unauthenticated', () => {
    test('all task list endpoints require auth', async ({ request }) => {
      const fakeId = '00000000-0000-0000-0000-000000000000'
      const responses = await Promise.all([
        request.get(`${API_BASE}/api/task-lists?workspace_id=${fakeId}`),
        request.post(`${API_BASE}/api/task-lists`, {
          data: { workspace_id: fakeId, name: 'My List' },
        }),
        request.put(`${API_BASE}/api/task-lists/${fakeId}`, {
          data: { name: 'Renamed' },
        }),
        request.delete(`${API_BASE}/api/task-lists/${fakeId}`),
        request.post(`${API_BASE}/api/task-lists/${fakeId}/items`, {
          data: { content: 'Item' },
        }),
        request.post(`${API_BASE}/api/task-lists/${fakeId}/clear-completed`),
      ])
      for (const response of responses) {
        expect(response.status()).toBe(401)
        const body = await response.json()
        expect(body.error).toBe('Authorization required')
      }
    })
  })

  test.describe('Task Lists API - Authenticated', () => {
    let apiContext: APIRequestContext
    let workspaceId: string

    test.beforeAll(async ({ playwright }) => {
      apiContext = await playwright.request.newContext()
      await getTestSession(apiContext, TEST_EMAIL, TEST_NAME)
      workspaceId = await getWorkspaceId(apiContext)
    })

    test.afterAll(async () => {
      await apiContext.dispose()
    })

    test('GET /api/task-lists returns list of task lists', async () => {
      const response = await apiContext.get(
        `${API_BASE}/api/task-lists?workspace_id=${workspaceId}`
      )
      expect(response.ok()).toBeTruthy()
      const body = await response.json()
      expect(body).toHaveProperty('objects')
      expect(Array.isArray(body.objects)).toBeTruthy()
    })

    test('GET /api/task-lists returns 403 for non-member workspace', async () => {
      const fakeId = '00000000-0000-0000-0000-000000000000'
      const response = await apiContext.get(
        `${API_BASE}/api/task-lists?workspace_id=${fakeId}`
      )
      expect(response.status()).toBe(403)
    })

    test('POST /api/task-lists creates a task list', async () => {
      const response = await apiContext.post(`${API_BASE}/api/task-lists`, {
        data: { workspace_id: workspaceId, name: 'Groceries' },
      })
      expect(response.status()).toBe(201)
      const body = await response.json()
      const taskList = getObjectByType(body.objects, 'taskList')
      expect(taskList).toHaveProperty('id')
      expect(taskList?.name).toBe('Groceries')
      expect(taskList?.workspaceId).toBe(workspaceId)
    })

    test('POST /api/task-lists requires name', async () => {
      const response = await apiContext.post(`${API_BASE}/api/task-lists`, {
        data: { workspace_id: workspaceId },
      })
      expect(response.status()).toBe(400)
      const body = await response.json()
      expect(body.error).toBeTruthy()
    })

    test('full task list CRUD lifecycle', async () => {
      // Create
      const createResponse = await apiContext.post(
        `${API_BASE}/api/task-lists`,
        {
          data: { workspace_id: workspaceId, name: 'CRUD Test List' },
        }
      )
      expect(createResponse.status()).toBe(201)
      const createBody = await createResponse.json()
      const created = getObjectByType(createBody.objects, 'taskList')
      const listId = created!.id

      // Read — list appears in workspace GET
      const getResponse = await apiContext.get(
        `${API_BASE}/api/task-lists?workspace_id=${workspaceId}`
      )
      expect(getResponse.ok()).toBeTruthy()
      const getBody = await getResponse.json()
      const listed = getObjectsByType(getBody.objects, 'taskList')
      expect(listed.some((tl) => tl.id === listId)).toBeTruthy()

      // Update (rename)
      const updateResponse = await apiContext.put(
        `${API_BASE}/api/task-lists/${listId}`,
        { data: { name: 'Renamed List' } }
      )
      expect(updateResponse.ok()).toBeTruthy()
      const updateBody = await updateResponse.json()
      const updated = getObjectByType(updateBody.objects, 'taskList')
      expect(updated?.name).toBe('Renamed List')

      // Delete
      const deleteResponse = await apiContext.delete(
        `${API_BASE}/api/task-lists/${listId}`
      )
      expect(deleteResponse.ok()).toBeTruthy()
      const deleteBody = await deleteResponse.json()
      expect(deleteBody.deleted).toHaveLength(1)
      expect(deleteBody.deleted[0].objectType).toBe('taskList')
      expect(deleteBody.deleted[0].id).toBe(listId)

      // Verify deleted
      const verifyResponse = await apiContext.put(
        `${API_BASE}/api/task-lists/${listId}`,
        { data: { name: 'Ghost' } }
      )
      expect(verifyResponse.status()).toBe(410)
    })

    test('task item add, complete, update, and delete lifecycle', async () => {
      const listId = await createTaskList(
        apiContext,
        workspaceId,
        'Item Test List'
      )

      // Add item
      const addResponse = await apiContext.post(
        `${API_BASE}/api/task-lists/${listId}/items`,
        { data: { content: 'Buy milk' } }
      )
      expect(addResponse.status()).toBe(201)
      const addBody = await addResponse.json()
      const item = getObjectByType(addBody.objects, 'taskItem')
      expect(item).toHaveProperty('id')
      expect(item?.content).toBe('Buy milk')
      expect(item?.completedAt).toBeNull()
      const itemId = item!.id

      // Mark complete
      const completeResponse = await apiContext.put(
        `${API_BASE}/api/task-lists/${listId}/items/${itemId}`,
        { data: { completed: true } }
      )
      expect(completeResponse.ok()).toBeTruthy()
      const completeBody = await completeResponse.json()
      const completed = getObjectByType(completeBody.objects, 'taskItem')
      expect(completed?.completedAt).not.toBeNull()

      // Mark incomplete
      const uncompleteResponse = await apiContext.put(
        `${API_BASE}/api/task-lists/${listId}/items/${itemId}`,
        { data: { completed: false } }
      )
      expect(uncompleteResponse.ok()).toBeTruthy()
      const uncompleteBody = await uncompleteResponse.json()
      const uncompleted = getObjectByType(uncompleteBody.objects, 'taskItem')
      expect(uncompleted?.completedAt).toBeNull()

      // Update content
      const editResponse = await apiContext.put(
        `${API_BASE}/api/task-lists/${listId}/items/${itemId}`,
        { data: { content: 'Buy oat milk' } }
      )
      expect(editResponse.ok()).toBeTruthy()
      const editBody = await editResponse.json()
      const edited = getObjectByType(editBody.objects, 'taskItem')
      expect(edited?.content).toBe('Buy oat milk')

      // Delete item
      const deleteResponse = await apiContext.delete(
        `${API_BASE}/api/task-lists/${listId}/items/${itemId}`
      )
      expect(deleteResponse.ok()).toBeTruthy()
      const deleteBody = await deleteResponse.json()
      expect(deleteBody.deleted[0].objectType).toBe('taskItem')
      expect(deleteBody.deleted[0].id).toBe(itemId)
    })

    test('POST /api/task-lists/:id/items requires content', async () => {
      const listId = await createTaskList(
        apiContext,
        workspaceId,
        'Validation List'
      )
      const response = await apiContext.post(
        `${API_BASE}/api/task-lists/${listId}/items`,
        { data: {} }
      )
      expect(response.status()).toBe(400)
    })

    test('POST /api/task-lists/:id/clear-completed removes only completed items', async () => {
      const listId = await createTaskList(
        apiContext,
        workspaceId,
        'Clear Test List'
      )
      const keepId = await addTaskItem(apiContext, listId, 'Keep me')
      const clearId = await addTaskItem(apiContext, listId, 'Clear me')

      // Mark the second item complete
      await apiContext.put(
        `${API_BASE}/api/task-lists/${listId}/items/${clearId}`,
        { data: { completed: true } }
      )

      const clearResponse = await apiContext.post(
        `${API_BASE}/api/task-lists/${listId}/clear-completed`
      )
      expect(clearResponse.ok()).toBeTruthy()
      const clearBody = await clearResponse.json()
      const deleted = clearBody.deleted as Array<{ id: string }>
      expect(deleted.some((d) => d.id === clearId)).toBeTruthy()
      expect(deleted.some((d) => d.id === keepId)).toBeFalsy()
    })
  })

  test.describe('Tasks UI - Unauthenticated', () => {
    test('tasks page redirects to login when not authenticated', async ({
      page,
    }) => {
      await page.goto('/tasks')
      await expect(page).toHaveURL('/login')
    })
  })

  test.describe('Tasks UI - Authenticated', () => {
    let sessionToken: string
    let apiContext: APIRequestContext
    let workspaceId: string
    // Unique suffix prevents collisions with accumulated data from previous runs
    const uid = Date.now()

    test.beforeAll(async ({ playwright }) => {
      apiContext = await playwright.request.newContext()
      const { token } = await getTestSession(apiContext, TEST_EMAIL, TEST_NAME)
      sessionToken = token
      workspaceId = await getWorkspaceId(apiContext)
    })

    test.afterAll(async () => {
      await apiContext.dispose()
    })

    test('tasks page shows header and New List button', async ({ page }) => {
      await setupAuthenticatedPage(page, sessionToken)
      await page.goto('/tasks')

      await expect(page.getByTestId('page-title')).toContainText('Tasks')
      await expect(page.getByTestId('add-task-list-button')).toBeVisible()
    })

    test('navigation includes Tasks link', async ({ page }) => {
      await setupAuthenticatedPage(page, sessionToken)
      await page.goto('/')

      await expect(page.getByRole('link', { name: 'Tasks' })).toBeVisible()
    })

    test('New List button opens the create modal', async ({ page }) => {
      await setupAuthenticatedPage(page, sessionToken)
      await page.goto('/tasks')

      await page.getByTestId('add-task-list-button').click()

      await expect(page.getByRole('dialog')).toBeVisible()
      await expect(
        page.getByRole('dialog').getByRole('heading', { name: 'New Task List' })
      ).toBeVisible()
      await expect(page.getByLabel('Name')).toBeVisible()
      await expect(page.getByTestId('submit-button')).toBeVisible()
    })

    test('can create a task list through the modal', async ({ page }) => {
      await setupAuthenticatedPage(page, sessionToken)
      await page.goto('/tasks')

      const listName = `Shopping List ${uid}`
      await page.getByTestId('add-task-list-button').click()
      await page.getByLabel('Name').fill(listName)
      await page.getByTestId('submit-button').click()

      await expect(page.getByRole('dialog')).not.toBeVisible()
      await expect(page.getByText(listName)).toBeVisible()
    })

    test('can add an item to a task list', async ({ page }) => {
      const listName = `Add Item List ${uid}`
      await createTaskList(apiContext, workspaceId, listName)

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto('/tasks')

      const card = page
        .getByTestId('task-list-card')
        .filter({ hasText: listName })
      await expect(card).toBeVisible()

      await card.getByPlaceholder('Add an item...').fill('Pick up dry cleaning')
      await card.getByPlaceholder('Add an item...').press('Enter')

      await expect(card.getByText('Pick up dry cleaning')).toBeVisible()
    })

    test('can check and uncheck a task item', async ({ page }) => {
      const listName = `Checkbox List ${uid}`
      const listId = await createTaskList(apiContext, workspaceId, listName)
      await addTaskItem(apiContext, listId, 'Do the thing')

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto('/tasks')

      const card = page
        .getByTestId('task-list-card')
        .filter({ hasText: listName })
      await expect(card.getByText('Do the thing')).toBeVisible()

      // Check it
      const checkbox = card.getByRole('checkbox')
      await checkbox.check()
      await expect(card.getByText('Do the thing')).toHaveClass(/line-through/)

      // Uncheck it
      await checkbox.uncheck()
      await expect(card.getByText('Do the thing')).not.toHaveClass(
        /line-through/
      )
    })

    test('can rename a task list', async ({ page }) => {
      const oldName = `Rename Me ${uid}`
      const newName = `Renamed ${uid}`
      await createTaskList(apiContext, workspaceId, oldName)

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto('/tasks')

      const card = page
        .getByTestId('task-list-card')
        .filter({ hasText: oldName })
      await expect(card).toBeVisible()

      await card.getByTitle('Rename list').click()

      // After clicking rename, the h2 disappears (v-if) so the card no longer has
      // visible text matching oldName. Find the rename input by absence of placeholder.
      const renameInput = page.locator(
        '[data-testid="task-list-card"] input[type="text"]:not([placeholder])'
      )
      await renameInput.fill(newName)
      await renameInput.press('Enter')

      await expect(page.getByText(newName)).toBeVisible()
    })

    test('can delete a task list', async ({ page }) => {
      const listName = `Delete Me ${uid}`
      await createTaskList(apiContext, workspaceId, listName)

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto('/tasks')

      const card = page
        .getByTestId('task-list-card')
        .filter({ hasText: listName })
      await expect(card).toBeVisible()

      await card.getByTitle('Delete list').click()

      await expect(card).not.toBeVisible()
    })

    test('clear completed button appears and removes completed items', async ({
      page,
    }) => {
      const listName = `Clear Test ${uid}`
      const listId = await createTaskList(apiContext, workspaceId, listName)
      await addTaskItem(apiContext, listId, 'Keep this')
      await addTaskItem(apiContext, listId, 'Mark done')

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto('/tasks')

      const card = page
        .getByTestId('task-list-card')
        .filter({ hasText: listName })
      await expect(card.getByText('Keep this')).toBeVisible()
      await expect(card.getByText('Mark done')).toBeVisible()

      // Complete the second item (select by row content to avoid order sensitivity)
      await card
        .locator('li')
        .filter({ hasText: 'Mark done' })
        .getByRole('checkbox')
        .check()

      // Clear completed button should appear
      await expect(card.getByText(/Clear 1 completed/)).toBeVisible()
      await card.getByText(/Clear 1 completed/).click()

      await expect(card.getByText('Mark done')).not.toBeVisible()
      await expect(card.getByText('Keep this')).toBeVisible()
      await expect(card.getByText(/Clear.*completed/)).not.toBeVisible()
    })
  })
})
