import { test, expect, APIRequestContext } from '@playwright/test'
import {
  PAGE_LOAD_TIMEOUT,
  getTestSession,
  setupAuthenticatedPage,
  getWorkspaceId,
  createTaskList,
  addTaskItem,
  newApiContext,
} from '../helpers'

const TEST_EMAIL = 'e2e-tasks-keyboard@example.com'
const TEST_NAME = 'E2E Tasks Keyboard User'

test.describe('Task Keyboard Navigation', () => {
  let sessionToken: string
  let apiContext: APIRequestContext
  let workspaceId: string
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

  test('j and k navigate between items', async ({ page }) => {
    const listId = await createTaskList(
      apiContext,
      workspaceId,
      `KB Nav ${uid}`
    )
    await addTaskItem(apiContext, listId, 'Alpha')
    await addTaskItem(apiContext, listId, 'Beta')
    await addTaskItem(apiContext, listId, 'Gamma')

    await setupAuthenticatedPage(page, sessionToken)
    await page.goto('/tasks')

    const card = page
      .getByTestId('task-list-card')
      .filter({ hasText: `KB Nav ${uid}` })
    const rows = card.getByTestId('task-item-row')

    // Wait for all items to be visible
    await expect(card.getByText('Gamma')).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })

    // Hover Alpha to establish starting position
    await rows.nth(0).hover()
    await expect(rows.nth(0)).toHaveAttribute('data-highlighted', 'true')

    // j moves to Beta
    await page.keyboard.press('j')
    await expect(rows.nth(1)).toHaveAttribute('data-highlighted', 'true')
    await expect(rows.nth(0)).not.toHaveAttribute('data-highlighted', 'true')

    // j moves to Gamma
    await page.keyboard.press('j')
    await expect(rows.nth(2)).toHaveAttribute('data-highlighted', 'true')
    await expect(rows.nth(1)).not.toHaveAttribute('data-highlighted', 'true')

    // k moves back to Beta
    await page.keyboard.press('k')
    await expect(rows.nth(1)).toHaveAttribute('data-highlighted', 'true')
    await expect(rows.nth(2)).not.toHaveAttribute('data-highlighted', 'true')

    // k moves back to Alpha
    await page.keyboard.press('k')
    await expect(rows.nth(0)).toHaveAttribute('data-highlighted', 'true')
    await expect(rows.nth(1)).not.toHaveAttribute('data-highlighted', 'true')
  })

  test('space toggles completion of highlighted item', async ({ page }) => {
    const listId = await createTaskList(
      apiContext,
      workspaceId,
      `KB Space ${uid}`
    )
    await addTaskItem(apiContext, listId, 'Toggle me')

    await setupAuthenticatedPage(page, sessionToken)
    await page.goto('/tasks')

    const card = page
      .getByTestId('task-list-card')
      .filter({ hasText: `KB Space ${uid}` })
    const row = card.getByTestId('task-item-row').first()
    const text = card.getByText('Toggle me')

    await expect(row).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })
    await row.hover()
    await expect(row).toHaveAttribute('data-highlighted', 'true')

    // Space completes the item
    await page.keyboard.press('Space')
    await expect(text).toHaveAttribute('data-completed', 'true')

    // Space again uncompletes it
    await page.keyboard.press('Space')
    await expect(text).not.toHaveAttribute('data-completed', 'true')
  })

  test('backspace deletes highlighted item and moves to next', async ({
    page,
  }) => {
    const listId = await createTaskList(
      apiContext,
      workspaceId,
      `KB Delete ${uid}`
    )
    await addTaskItem(apiContext, listId, 'Delete me')
    await addTaskItem(apiContext, listId, 'Keep me')

    await setupAuthenticatedPage(page, sessionToken)
    await page.goto('/tasks')

    const card = page
      .getByTestId('task-list-card')
      .filter({ hasText: `KB Delete ${uid}` })
    const rows = card.getByTestId('task-item-row')

    await expect(rows.nth(0)).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })
    await rows.nth(0).hover()
    await page.keyboard.press('Backspace')

    await expect(card.getByText('Delete me')).not.toBeVisible()
    await expect(rows.first()).toHaveAttribute('data-highlighted', 'true')
    await expect(card.getByText('Keep me')).toBeVisible()
  })

  test('backspace on the second item in a list deletes it', async ({
    page,
  }) => {
    const listId = await createTaskList(
      apiContext,
      workspaceId,
      `KB Delete Last ${uid}`
    )
    await addTaskItem(apiContext, listId, 'Keep me')
    await addTaskItem(apiContext, listId, 'Delete me')
    await addTaskItem(apiContext, listId, 'Also keep me')

    await setupAuthenticatedPage(page, sessionToken)
    await page.goto('/tasks')

    const card = page
      .getByTestId('task-list-card')
      .filter({ hasText: `KB Delete Last ${uid}` })
    const rows = card.getByTestId('task-item-row')

    await expect(card.getByText('Also keep me')).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })

    await rows.nth(1).hover()
    await page.keyboard.press('Backspace')

    await expect(card.getByText('Delete me')).not.toBeVisible()
    await expect(card.getByText('Keep me', { exact: true })).toBeVisible()
    await expect(card.getByText('Also keep me')).toBeVisible()
  })

  test('i focuses the add-input of the highlighted list', async ({ page }) => {
    const listId = await createTaskList(
      apiContext,
      workspaceId,
      `KB Input ${uid}`
    )
    await addTaskItem(apiContext, listId, 'An item')

    await setupAuthenticatedPage(page, sessionToken)
    await page.goto('/tasks')

    const card = page
      .getByTestId('task-list-card')
      .filter({ hasText: `KB Input ${uid}` })
    const addInput = card.getByPlaceholder('Add an item...')
    const row = card.getByTestId('task-item-row').first()

    await expect(row).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })
    await row.hover()
    await page.keyboard.press('i')

    await expect(addInput).toBeFocused()
  })

  test('mouse hover moves the highlight', async ({ page }) => {
    const listId = await createTaskList(
      apiContext,
      workspaceId,
      `KB Hover ${uid}`
    )
    await addTaskItem(apiContext, listId, 'First')
    await addTaskItem(apiContext, listId, 'Second')

    await setupAuthenticatedPage(page, sessionToken)
    await page.goto('/tasks')

    const card = page
      .getByTestId('task-list-card')
      .filter({ hasText: `KB Hover ${uid}` })
    const rows = card.getByTestId('task-item-row')

    await expect(rows.nth(0)).toBeVisible({ timeout: PAGE_LOAD_TIMEOUT })
    await rows.nth(0).hover()
    await expect(rows.nth(0)).toHaveAttribute('data-highlighted', 'true')
    await expect(rows.nth(1)).not.toHaveAttribute('data-highlighted', 'true')

    await rows.nth(1).hover()
    await expect(rows.nth(1)).toHaveAttribute('data-highlighted', 'true')
    await expect(rows.nth(0)).not.toHaveAttribute('data-highlighted', 'true')
  })

  test('escape in add-input blurs it and re-enables keyboard navigation', async ({
    page,
  }) => {
    const listId = await createTaskList(
      apiContext,
      workspaceId,
      `KB Escape ${uid}`
    )
    await addTaskItem(apiContext, listId, 'First item')
    await addTaskItem(apiContext, listId, 'Second item')

    await setupAuthenticatedPage(page, sessionToken)
    await page.goto('/tasks')

    const card = page
      .getByTestId('task-list-card')
      .filter({ hasText: `KB Escape ${uid}` })
    const addInput = card.getByPlaceholder('Add an item...')
    const rows = card.getByTestId('task-item-row')

    await expect(card.getByText('Second item')).toBeVisible({
      timeout: PAGE_LOAD_TIMEOUT,
    })

    // Hover first item so that i targets this list's add-input
    await rows.nth(0).hover()
    await expect(rows.nth(0)).toHaveAttribute('data-highlighted', 'true')

    await page.keyboard.press('i')
    await expect(addInput).toBeFocused()

    // j while input is focused does not move the highlight
    await page.keyboard.press('j')
    await expect(rows.nth(0)).toHaveAttribute('data-highlighted', 'true')

    // Escape blurs the input
    await page.keyboard.press('Escape')
    await expect(addInput).not.toBeFocused()

    // j now moves the highlight to the next item in the list
    await page.keyboard.press('j')
    await expect(rows.nth(1)).toHaveAttribute('data-highlighted', 'true')
    await expect(rows.nth(0)).not.toHaveAttribute('data-highlighted', 'true')
  })
})
