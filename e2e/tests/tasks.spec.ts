import { test, expect, APIRequestContext } from '@playwright/test'
import {
  API_BASE,
  PAGE_LOAD_TIMEOUT,
  getObjectByType,
  getObjectsByType,
  getTestSession,
  setupAuthenticatedPage,
  getWorkspaceId,
  createTaskList,
  addTaskItem,
  newApiContext,
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
      apiContext = await newApiContext(playwright)
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
      apiContext = await newApiContext(playwright)
      const { token } = await getTestSession(apiContext, TEST_EMAIL, TEST_NAME)
      sessionToken = token
      workspaceId = await getWorkspaceId(apiContext)
    })

    test.afterAll(async () => {
      await apiContext.dispose()
    })

    test('page layout, navigation, and creating a list via modal', async ({
      page,
    }) => {
      await setupAuthenticatedPage(page, sessionToken)

      // Navigation includes Tasks link
      await page.goto('/')
      await expect(page.getByRole('link', { name: 'Tasks' })).toBeVisible({
        timeout: PAGE_LOAD_TIMEOUT,
      })

      // Tasks page shows header and New List button
      await page.goto('/tasks')
      await expect(page.getByTestId('page-title')).toContainText('Tasks', {
        timeout: PAGE_LOAD_TIMEOUT,
      })
      await expect(page.getByTestId('add-task-list-button')).toBeVisible()

      // New List button reveals inline input
      await page.getByTestId('add-task-list-button').click()
      await expect(page.getByTestId('new-list-form')).toBeVisible()
      await expect(page.getByTestId('new-list-name-input')).toBeFocused()
      await expect(page.getByTestId('submit-button')).toBeVisible()

      // Can create a task list through the inline form
      const listName = `Shopping List ${uid}`
      await page.getByTestId('new-list-name-input').fill(listName)
      await page.getByTestId('submit-button').click()

      await expect(page.getByTestId('new-list-form')).not.toBeVisible()
      await expect(page.getByText(listName)).toBeVisible()
    })

    test('add items, check, and clear completed', async ({ page }) => {
      const listName = `Items List ${uid}`
      await createTaskList(apiContext, workspaceId, listName)

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto('/tasks')

      const card = page
        .getByTestId('task-list-card')
        .filter({ hasText: listName })
      await expect(card).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })

      // Add two items so clearing can distinguish completed from not
      await card.getByPlaceholder('Add an item...').fill('Keep this')
      await card.getByPlaceholder('Add an item...').press('Enter')
      await expect(card.getByText('Keep this')).toBeVisible()

      await card.getByPlaceholder('Add an item...').fill('Mark done')
      await card.getByPlaceholder('Add an item...').press('Enter')
      await expect(card.getByText('Mark done')).toBeVisible()

      // Check one item and verify the DOM reflects the completed state
      const markDoneCheckbox = card
        .getByTestId('task-item-row')
        .filter({ hasText: 'Mark done' })
        .getByRole('checkbox')
      await markDoneCheckbox.check()
      await expect(card.getByText('Mark done')).toHaveAttribute(
        'data-completed',
        'true'
      )

      // Clear completed: button appears, click it, only the checked item goes.
      // (An earlier version of this test also did an uncheck + re-check in
      // between, producing three overlapping PUT /items/:id requests and a
      // rare race under CI load. Uncheck is covered at the API level by the
      // "task item add, complete, update, and delete lifecycle" test above.)
      const clearBtn = card.getByTestId('clear-completed-button')
      await expect(clearBtn).toBeVisible()
      await clearBtn.click()

      await expect(card.getByText('Mark done')).not.toBeVisible()
      await expect(card.getByText('Keep this')).toBeVisible()
      await expect(clearBtn).not.toBeVisible()
    })

    test('rename and delete a task list', async ({ page }) => {
      const oldName = `Rename Me ${uid}`
      const newName = `Renamed ${uid}`
      await createTaskList(apiContext, workspaceId, oldName)

      const deleteName = `Delete Me ${uid}`
      await createTaskList(apiContext, workspaceId, deleteName)

      await setupAuthenticatedPage(page, sessionToken)
      await page.goto('/tasks')

      // Rename
      const renameCard = page
        .getByTestId('task-list-card')
        .filter({ hasText: oldName })
      await expect(renameCard).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })

      await renameCard.getByTestId('rename-list-button').click()

      // After clicking rename, the h2 disappears (v-if) so the card text filter
      // no longer matches. Find the visible rename input directly on the page.
      const renameInput = page.getByTestId('rename-list-input')
      await renameInput.fill(newName)
      await renameInput.press('Enter')

      await expect(page.getByText(newName)).toBeVisible()

      // Delete
      const deleteCard = page
        .getByTestId('task-list-card')
        .filter({ hasText: deleteName })
      await expect(deleteCard).toBeVisible()

      await deleteCard.getByTestId('delete-list-button').click()

      await expect(deleteCard).not.toBeVisible()
    })
  })
})
