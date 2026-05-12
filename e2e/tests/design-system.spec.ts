import { test, expect } from '@playwright/test'

// /design is a static gallery page that renders every primitive in light and
// dark side-by-side. A baseline screenshot is the cheapest visual regression
// gate: any drift in a primitive — color, spacing, ring, weight — fails this
// test and shows up as a diff in the Playwright report.
//
// Baselines live in design-system.spec.ts-snapshots/ next to this file. Run
// `pnpm exec playwright test design-system --update-snapshots` to refresh
// after intentional design changes.
test.describe('Design system gallery', () => {
  test('renders every primitive in both modes without visual drift', async ({
    page,
  }) => {
    await page.goto('/design')

    // Block until fonts have loaded so the snapshot is text-stable.
    await page.evaluate(() => document.fonts.ready)

    // The gallery has no async data, but give Vue a tick to settle.
    await expect(page.getByText('Design system').first()).toBeVisible()

    await expect(page).toHaveScreenshot('design-gallery.png', {
      fullPage: true,
      // Animations like the modal entrance are non-deterministic; freeze them.
      animations: 'disabled',
      // Allow ~1% pixel drift to absorb subpixel font rendering across runs.
      maxDiffPixelRatio: 0.01,
    })
  })

  // The unit tests for BaseModal stub jsdom's missing dialog methods. Run the
  // close routes end-to-end here so we know they actually work in a real
  // browser: the X button, the dialog's `close` event (what Escape fires),
  // and the backdrop click that maps to the same path.
  test('opens and closes the modal from the X button and Escape', async ({
    page,
  }) => {
    await page.goto('/design')

    await page.getByRole('button', { name: 'Open modal' }).first().click()
    const dialog = page.getByRole('dialog')
    await expect(dialog).toBeVisible()

    await dialog.getByRole('button', { name: 'Close' }).click()
    await expect(dialog).toBeHidden()

    await page.getByRole('button', { name: 'Open modal' }).first().click()
    await expect(dialog).toBeVisible()

    await page.keyboard.press('Escape')
    await expect(dialog).toBeHidden()
  })
})
