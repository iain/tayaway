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
  newApiContext,
} from '../helpers'

const TEST_EMAIL = 'e2e-tasks-sorting@example.com'
const TEST_NAME = 'E2E Tasks Sorting User'

test.describe('Task Sorting', () => {
  test.describe('API - Task Positioning', () => {
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

    test.describe('Task List Positioning', () => {
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
        const idA = await createTaskList(
          apiContext,
          workspaceId,
          'List A Order'
        )
        const idB = await createTaskList(
          apiContext,
          workspaceId,
          'List B Order'
        )

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

    test.describe('Task Item Positioning', () => {
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
  })

  // Each drag test uses its own user/workspace to avoid interference from
  // parallel tests that create task lists in the same workspace (which causes
  // page reflows that break drag coordinates).
  test.describe('UI - Drag-and-Drop', () => {
    test('drag handles are visible on task lists and items', async ({
      page,
      request,
    }) => {
      const email = `e2e-dnd-handles-${crypto.randomUUID()}@example.com`
      const { token } = await getTestSession(request, email, TEST_NAME)
      const workspaceId = await getWorkspaceId(request)

      const listId = await createTaskList(request, workspaceId, 'Handle List')
      await addTaskItem(request, listId, 'Handle test item')

      await setupAuthenticatedPage(page, token)
      await page.goto('/tasks')

      const card = page
        .getByTestId('task-list-card')
        .filter({ hasText: 'Handle List' })
      await expect(card.getByText('Handle test item')).toBeVisible()
      await expect(
        page.getByTestId('task-list-drag-handle').first()
      ).toBeVisible()
      await expect(card.getByTestId('task-item-drag-handle')).toBeVisible()
    })

    test('can reorder task lists by dragging', async ({ page, request }) => {
      const email = `e2e-dnd-reorder-${crypto.randomUUID()}@example.com`
      const { token } = await getTestSession(request, email, TEST_NAME)
      const workspaceId = await getWorkspaceId(request)

      // Create Alpha first (gets lower position), Beta second (gets higher position)
      await createTaskList(request, workspaceId, 'Alpha List')
      await createTaskList(request, workspaceId, 'Beta List')

      await setupAuthenticatedPage(page, token)
      await page.goto('/tasks')

      const cards = page.getByTestId('task-list-card')
      const alphaCard = cards.filter({ hasText: 'Alpha List' })
      const betaCard = cards.filter({ hasText: 'Beta List' })
      await expect(alphaCard).toBeVisible()
      await expect(betaCard).toBeVisible()

      const betaHandle = betaCard.getByTestId('task-list-drag-handle')
      const alphaHandle = alphaCard.getByTestId('task-list-drag-handle')

      // SortableJS uses the HTML5 Drag API, so Playwright's dragTo is the
      // most reliable approach. Wrap in toPass to retry on misfire.
      await expect(async () => {
        await betaHandle.dragTo(alphaHandle)

        const allCards = await page.getByTestId('task-list-card').all()
        const texts = await Promise.all(allCards.map((c) => c.textContent()))
        const betaIdx = texts.findIndex((t) => t?.includes('Beta List'))
        const alphaIdx = texts.findIndex((t) => t?.includes('Alpha List'))
        expect(betaIdx).toBeGreaterThan(-1)
        expect(alphaIdx).toBeGreaterThan(-1)
        expect(betaIdx).toBeLessThan(alphaIdx)
      }).toPass({ timeout: 15_000 })
    })

    test('can reorder items within a task list by dragging', async ({
      page,
      request,
    }) => {
      const email = `e2e-dnd-items-${crypto.randomUUID()}@example.com`
      const { token } = await getTestSession(request, email, TEST_NAME)
      const workspaceId = await getWorkspaceId(request)

      const listId = await createTaskList(request, workspaceId, 'Sort List')
      await addTaskItem(request, listId, 'First item')
      await addTaskItem(request, listId, 'Second item')

      await setupAuthenticatedPage(page, token)
      await page.goto('/tasks')

      const card = page
        .getByTestId('task-list-card')
        .filter({ hasText: 'Sort List' })
      await expect(card.getByText('First item')).toBeVisible()
      await expect(card.getByText('Second item')).toBeVisible()

      const firstRow = card
        .getByTestId('task-item-row')
        .filter({ hasText: 'First item' })
      const secondRow = card
        .getByTestId('task-item-row')
        .filter({ hasText: 'Second item' })
      const secondHandle = secondRow.getByTestId('task-item-drag-handle')
      const firstHandle = firstRow.getByTestId('task-item-drag-handle')

      // SortableJS uses the HTML5 Drag API, so Playwright's dragTo is the
      // most reliable approach. Wrap in toPass to retry on misfire.
      await expect(async () => {
        await secondHandle.dragTo(firstHandle)

        await expect(card.getByTestId('task-item-row').first()).toContainText(
          'Second item'
        )
      }).toPass({ timeout: 15_000 })
    })

    test('can move item between task lists by dragging', async ({
      page,
      request,
    }) => {
      const email = `e2e-dnd-cross-${crypto.randomUUID()}@example.com`
      const { token } = await getTestSession(request, email, TEST_NAME)
      const workspaceId = await getWorkspaceId(request)

      // List B needs a visible item as a drop target — dragging to an empty
      // list's tiny min-h-8 container is unreliable with SortableJS + Playwright.
      const listAId = await createTaskList(request, workspaceId, 'List A')
      await addTaskItem(request, listAId, 'Move me')
      const listBId = await createTaskList(request, workspaceId, 'List B')
      await addTaskItem(request, listBId, 'Placeholder')

      await setupAuthenticatedPage(page, token)
      await page.goto('/tasks')

      const cardA = page
        .getByTestId('task-list-card')
        .filter({ hasText: 'List A' })
      const cardB = page
        .getByTestId('task-list-card')
        .filter({ hasText: 'List B' })

      await expect(cardA.getByText('Move me')).toBeVisible()

      const itemHandle = cardA
        .getByTestId('task-item-row')
        .filter({ hasText: 'Move me' })
        .getByTestId('task-item-drag-handle')
      const targetRow = cardB
        .getByTestId('task-item-row')
        .filter({ hasText: 'Placeholder' })

      // dragTo() moves too fast for SortableJS cross-list events, so we drive
      // the mouse manually. The whole drag+assertion is wrapped in toPass so
      // that if the drag misfires, we re-measure and retry.
      await expect(async () => {
        await itemHandle.evaluate((el) =>
          el.scrollIntoView({ block: 'center', behavior: 'instant' })
        )
        const [sourceBox, targetBox] = await Promise.all([
          itemHandle.boundingBox(),
          targetRow.boundingBox(),
        ])
        if (!sourceBox || !targetBox)
          throw new Error('Elements not in viewport')
        const sx = sourceBox.x + sourceBox.width / 2
        const sy = sourceBox.y + sourceBox.height / 2
        const tx = targetBox.x + targetBox.width / 2
        const ty = targetBox.y + targetBox.height / 2

        await page.mouse.move(sx, sy)
        await page.mouse.down()
        await page.mouse.move(sx, sy - 10, { steps: 10 })
        await page.mouse.move(tx, ty, { steps: 30 })
        await page.mouse.up()

        await expect(cardA.getByText('Move me')).not.toBeVisible()
      }).toPass({ timeout: 20_000 })

      // Verify item arrived in B (outside toPass — by this point the move is done)
      await expect(cardB.getByText('Move me')).toBeVisible()
    })
  })
})
