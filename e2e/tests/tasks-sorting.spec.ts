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

const TEST_EMAIL = 'e2e-tasks-sorting@example.com'
const TEST_NAME = 'E2E Tasks Sorting User'

test.describe('Task Sorting', () => {
  test.describe('API - Task List Positioning', () => {
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

    test('newly created task list has a numeric position', async () => {
      const response = await apiContext.post(`${API_BASE}/api/task-lists`, {
        data: { workspace_id: workspaceId, name: 'Position Test List' },
      })
      expect(response.status()).toBe(201)
      const body = await response.json()
      const taskList = getObjectByType(body.objects, 'taskList')
      expect(typeof taskList?.position).toBe('number')
    })

    test('PUT task list with position updates position and returns updated list', async () => {
      const listId = await createTaskList(
        apiContext,
        workspaceId,
        'Reposition Test'
      )

      const response = await apiContext.put(
        `${API_BASE}/api/task-lists/${listId}`,
        { data: { position: 99.5 } }
      )
      expect(response.ok()).toBeTruthy()
      const body = await response.json()
      const taskList = getObjectByType(body.objects, 'taskList')
      expect(taskList?.id).toBe(listId)
      expect(taskList?.position).toBe(99.5)
    })

    test('GET task lists returns lists ordered by position', async () => {
      // Create two lists and explicitly set their positions
      const idA = await createTaskList(apiContext, workspaceId, 'List A Order')
      const idB = await createTaskList(apiContext, workspaceId, 'List B Order')

      // Set B to position 1, A to position 2 (reverse creation order)
      await apiContext.put(`${API_BASE}/api/task-lists/${idB}`, {
        data: { position: 1.0 },
      })
      await apiContext.put(`${API_BASE}/api/task-lists/${idA}`, {
        data: { position: 2.0 },
      })

      const getResponse = await apiContext.get(
        `${API_BASE}/api/task-lists?workspace_id=${workspaceId}`
      )
      const getBody = await getResponse.json()
      const lists = getObjectsByType(getBody.objects, 'taskList') as Array<{
        id: string
        position: number
      }>

      const relevant = lists.filter((l) => l.id === idA || l.id === idB)
      expect(relevant).toHaveLength(2)
      // B (pos 1) should appear before A (pos 2)
      expect(relevant[0].id).toBe(idB)
      expect(relevant[1].id).toBe(idA)
    })

    test('PUT task list with name and position updates both fields', async () => {
      const listId = await createTaskList(
        apiContext,
        workspaceId,
        'Combined Update'
      )

      const response = await apiContext.put(
        `${API_BASE}/api/task-lists/${listId}`,
        { data: { name: 'Renamed And Repositioned', position: 55.0 } }
      )
      expect(response.ok()).toBeTruthy()
      const body = await response.json()
      const taskList = getObjectByType(body.objects, 'taskList')
      expect(taskList?.name).toBe('Renamed And Repositioned')
      expect(taskList?.position).toBe(55.0)
    })

    test('PUT task list without name or position returns 400', async () => {
      const listId = await createTaskList(
        apiContext,
        workspaceId,
        'Validation Test'
      )

      const response = await apiContext.put(
        `${API_BASE}/api/task-lists/${listId}`,
        { data: {} }
      )
      expect(response.status()).toBe(400)
    })
  })

  test.describe('API - Task Item Positioning', () => {
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

    test('newly created task item has a numeric position', async () => {
      const listId = await createTaskList(
        apiContext,
        workspaceId,
        'Item Position Test'
      )
      const response = await apiContext.post(
        `${API_BASE}/api/task-lists/${listId}/items`,
        { data: { content: 'Positioned item' } }
      )
      expect(response.status()).toBe(201)
      const body = await response.json()
      const item = getObjectByType(body.objects, 'taskItem')
      expect(typeof item?.position).toBe('number')
    })

    test('PUT task item with position updates position', async () => {
      const listId = await createTaskList(
        apiContext,
        workspaceId,
        'Item Reposition'
      )
      const itemId = await addTaskItem(apiContext, listId, 'Reposition me')

      const response = await apiContext.put(
        `${API_BASE}/api/task-lists/${listId}/items/${itemId}`,
        { data: { position: 77.5 } }
      )
      expect(response.ok()).toBeTruthy()
      const body = await response.json()
      const item = getObjectByType(body.objects, 'taskItem')
      expect(item?.id).toBe(itemId)
      expect(item?.position).toBe(77.5)
    })

    test('PUT task item with task_list_id moves item to target list', async () => {
      const sourceListId = await createTaskList(
        apiContext,
        workspaceId,
        'Source List Move'
      )
      const targetListId = await createTaskList(
        apiContext,
        workspaceId,
        'Target List Move'
      )
      const itemId = await addTaskItem(apiContext, sourceListId, 'Move me')

      const response = await apiContext.put(
        `${API_BASE}/api/task-lists/${sourceListId}/items/${itemId}`,
        { data: { task_list_id: targetListId } }
      )
      expect(response.ok()).toBeTruthy()
      const body = await response.json()
      const item = getObjectByType(body.objects, 'taskItem')
      expect(item?.id).toBe(itemId)
      expect((item as { taskListId: string })?.taskListId).toBe(targetListId)
    })

    test('PUT task item with position and task_list_id moves and repositions', async () => {
      const sourceListId = await createTaskList(
        apiContext,
        workspaceId,
        'Source Move+Pos'
      )
      const targetListId = await createTaskList(
        apiContext,
        workspaceId,
        'Target Move+Pos'
      )
      await addTaskItem(apiContext, targetListId, 'Existing item at 1')
      await apiContext.put(
        `${API_BASE}/api/task-lists/${targetListId}/items/${await addTaskItem(apiContext, targetListId, 'Existing item at 3')}`,
        { data: { position: 3.0 } }
      )
      const itemId = await addTaskItem(
        apiContext,
        sourceListId,
        'Move and place at 2'
      )

      const response = await apiContext.put(
        `${API_BASE}/api/task-lists/${sourceListId}/items/${itemId}`,
        { data: { task_list_id: targetListId, position: 2.0 } }
      )
      expect(response.ok()).toBeTruthy()
      const body = await response.json()
      const item = getObjectByType(body.objects, 'taskItem')
      expect((item as { taskListId: string })?.taskListId).toBe(targetListId)
      expect(item?.position).toBe(2.0)
    })

    test('existing item update still works without position or task_list_id', async () => {
      const listId = await createTaskList(
        apiContext,
        workspaceId,
        'Backwards Compat'
      )
      const itemId = await addTaskItem(apiContext, listId, 'Original content')

      const response = await apiContext.put(
        `${API_BASE}/api/task-lists/${listId}/items/${itemId}`,
        { data: { content: 'Updated content', completed: true } }
      )
      expect(response.ok()).toBeTruthy()
      const body = await response.json()
      const item = getObjectByType(body.objects, 'taskItem')
      expect(item?.content).toBe('Updated content')
      expect(item?.completedAt).not.toBeNull()
    })
  })

  test.describe('UI - Drag-and-Drop', () => {
    let sessionToken: string
    const uid = Date.now()

    test.beforeAll(async ({ playwright }) => {
      const ctx = await playwright.request.newContext()
      const { token } = await getTestSession(ctx, TEST_EMAIL, TEST_NAME)
      sessionToken = token
      await ctx.dispose()
    })

    test('drag handles are visible on task list cards', async ({ page }) => {
      await setupAuthenticatedPage(page, sessionToken)
      await page.goto('/tasks')

      const listName = `Drag Handle Test ${uid}`
      await page.getByTestId('add-task-list-button').click()
      await page.getByLabel('Name').fill(listName)
      await page.getByTestId('submit-button').click()
      await expect(page.getByRole('dialog')).not.toBeVisible({ timeout: 5000 })

      await expect(
        page.getByTestId('task-list-drag-handle').first()
      ).toBeVisible()
    })

    test('drag handles are visible on task items', async ({ page }) => {
      await setupAuthenticatedPage(page, sessionToken)
      await page.goto('/tasks')

      const listName = `Item Handle Test ${uid}`
      await page.getByTestId('add-task-list-button').click()
      await page.getByLabel('Name').fill(listName)
      await page.getByTestId('submit-button').click()
      await expect(page.getByRole('dialog')).not.toBeVisible({ timeout: 5000 })

      const card = page
        .getByTestId('task-list-card')
        .filter({ hasText: listName })
      await card.getByPlaceholder('Add an item...').fill('Handle test item')
      await card.getByPlaceholder('Add an item...').press('Enter')
      await expect(card.getByTestId('task-item-drag-handle')).toBeVisible({
        timeout: 5000,
      })
    })

    test('can reorder task lists by dragging', async ({ page }) => {
      await setupAuthenticatedPage(page, sessionToken)
      await page.goto('/tasks')

      const alphaName = `Alpha List ${uid}`
      const betaName = `Beta List ${uid}`

      // Create Alpha first (gets lower position)
      await page.getByTestId('add-task-list-button').click()
      await page.getByLabel('Name').fill(alphaName)
      await page.getByTestId('submit-button').click()
      await expect(page.getByRole('dialog')).not.toBeVisible({ timeout: 5000 })

      // Create Beta second (gets higher position)
      await page.getByTestId('add-task-list-button').click()
      await page.getByLabel('Name').fill(betaName)
      await page.getByTestId('submit-button').click()
      await expect(page.getByRole('dialog')).not.toBeVisible({ timeout: 5000 })

      // Verify initial order: Alpha before Beta
      const cards = page.getByTestId('task-list-card')
      const alphaCard = cards.filter({ hasText: alphaName })
      const betaCard = cards.filter({ hasText: betaName })
      await expect(alphaCard).toBeVisible()
      await expect(betaCard).toBeVisible()

      // Drag Beta's handle above Alpha
      const betaHandle = betaCard.getByTestId('task-list-drag-handle')
      const alphaHandle = alphaCard.getByTestId('task-list-drag-handle')

      await betaHandle.dragTo(alphaHandle)

      // Wait for UI to update and verify Beta is now before Alpha
      await expect(page.getByTestId('task-list-card').first()).toContainText(
        betaName,
        { timeout: 5000 }
      )
    })

    test('can reorder items within a task list by dragging', async ({
      page,
    }) => {
      await setupAuthenticatedPage(page, sessionToken)
      await page.goto('/tasks')

      const listName = `Item Sort List ${uid}`
      await page.getByTestId('add-task-list-button').click()
      await page.getByLabel('Name').fill(listName)
      await page.getByTestId('submit-button').click()
      await expect(page.getByRole('dialog')).not.toBeVisible({ timeout: 5000 })

      const card = page
        .getByTestId('task-list-card')
        .filter({ hasText: listName })

      // Add items
      await card.getByPlaceholder('Add an item...').fill('First item')
      await card.getByPlaceholder('Add an item...').press('Enter')
      await expect(card.getByText('First item')).toBeVisible()

      await card.getByPlaceholder('Add an item...').fill('Second item')
      await card.getByPlaceholder('Add an item...').press('Enter')
      await expect(card.getByText('Second item')).toBeVisible()

      // Verify initial order: First before Second
      const firstRow = card.locator('li').filter({ hasText: 'First item' })
      const secondRow = card.locator('li').filter({ hasText: 'Second item' })

      // Drag Second above First
      const secondHandle = secondRow.getByTestId('task-item-drag-handle')
      const firstHandle = firstRow.getByTestId('task-item-drag-handle')

      await secondHandle.dragTo(firstHandle)

      // Verify Second is now before First
      await expect(card.locator('li').first()).toContainText('Second item', {
        timeout: 5000,
      })
    })

    test('can move item between task lists by dragging', async ({ page }) => {
      await setupAuthenticatedPage(page, sessionToken)
      await page.goto('/tasks')

      const listAName = `List A Move ${uid}`
      const listBName = `List B Move ${uid}`

      // Create List A with an item
      await page.getByTestId('add-task-list-button').click()
      await page.getByLabel('Name').fill(listAName)
      await page.getByTestId('submit-button').click()
      await expect(page.getByRole('dialog')).not.toBeVisible({ timeout: 5000 })

      const cardA = page
        .getByTestId('task-list-card')
        .filter({ hasText: listAName })
      await cardA.getByPlaceholder('Add an item...').fill('Move me')
      await cardA.getByPlaceholder('Add an item...').press('Enter')
      await expect(cardA.getByText('Move me')).toBeVisible()

      // Create List B (empty)
      await page.getByTestId('add-task-list-button').click()
      await page.getByLabel('Name').fill(listBName)
      await page.getByTestId('submit-button').click()
      await expect(page.getByRole('dialog')).not.toBeVisible({ timeout: 5000 })

      const cardB = page
        .getByTestId('task-list-card')
        .filter({ hasText: listBName })

      // Drag the item from List A to List B
      const moveItem = cardA.locator('li').filter({ hasText: 'Move me' })
      const itemHandle = moveItem.getByTestId('task-item-drag-handle')

      await itemHandle.dragTo(cardB)

      // Verify item moved: gone from A, present in B
      await expect(cardA.getByText('Move me')).not.toBeVisible({
        timeout: 5000,
      })
      await expect(cardB.getByText('Move me')).toBeVisible({ timeout: 5000 })
    })
  })
})
