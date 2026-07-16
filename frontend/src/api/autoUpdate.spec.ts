import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'

// The module keeps state (the pending update callback and armed listeners),
// so each test re-imports a fresh copy via vi.resetModules().
async function importModule() {
  return await import('./autoUpdate')
}

function setVisibility(state: 'visible' | 'hidden'): void {
  Object.defineProperty(document, 'visibilityState', {
    configurable: true,
    get: () => state,
  })
}

describe('scheduleAutoUpdate', () => {
  beforeEach(() => {
    vi.resetModules()
    vi.useFakeTimers()
    setVisibility('visible')
  })

  afterEach(() => {
    vi.useRealTimers()
    delete (document as { visibilityState?: string }).visibilityState
    document.body.innerHTML = ''
  })

  it('applies immediately when scheduled while the tab is hidden', async () => {
    setVisibility('hidden')
    const apply = vi.fn()
    const { scheduleAutoUpdate } = await importModule()

    scheduleAutoUpdate(apply)

    expect(apply).toHaveBeenCalledOnce()
    expect(apply.mock.calls[0]?.[0]).toBeUndefined()
  })

  it('waits while the tab is visible and applies when it goes hidden', async () => {
    const apply = vi.fn()
    const { scheduleAutoUpdate } = await importModule()

    scheduleAutoUpdate(apply)
    expect(apply).not.toHaveBeenCalled()

    setVisibility('hidden')
    document.dispatchEvent(new Event('visibilitychange'))
    expect(apply).toHaveBeenCalledOnce()

    // A second visibility flap must not apply the update again
    document.dispatchEvent(new Event('visibilitychange'))
    expect(apply).toHaveBeenCalledOnce()
  })

  it('applies after the user has been idle for a while', async () => {
    const apply = vi.fn()
    const { scheduleAutoUpdate } = await importModule()

    scheduleAutoUpdate(apply)

    await vi.advanceTimersByTimeAsync(25_000)
    expect(apply).not.toHaveBeenCalled()

    await vi.advanceTimersByTimeAsync(10_000)
    expect(apply).toHaveBeenCalledOnce()
    expect(apply.mock.calls[0]?.[0]).toBeUndefined()
  })

  it('restarts the idle window on user activity', async () => {
    const apply = vi.fn()
    const { scheduleAutoUpdate } = await importModule()

    scheduleAutoUpdate(apply)

    await vi.advanceTimersByTimeAsync(25_000)
    window.dispatchEvent(new Event('pointerdown'))

    await vi.advanceTimersByTimeAsync(25_000)
    expect(apply).not.toHaveBeenCalled()

    await vi.advanceTimersByTimeAsync(10_000)
    expect(apply).toHaveBeenCalledOnce()
  })

  it('defers while a text field has focus, then applies after it blurs', async () => {
    const input = document.createElement('input')
    document.body.appendChild(input)
    input.focus()

    const apply = vi.fn()
    const { scheduleAutoUpdate } = await importModule()
    scheduleAutoUpdate(apply)

    await vi.advanceTimersByTimeAsync(60_000)
    expect(apply).not.toHaveBeenCalled()

    input.blur()
    await vi.advanceTimersByTimeAsync(10_000)
    expect(apply).toHaveBeenCalledOnce()
  })

  it('does not defer for a focused non-text control like a checkbox', async () => {
    const checkbox = document.createElement('input')
    checkbox.type = 'checkbox'
    document.body.appendChild(checkbox)
    checkbox.focus()

    const apply = vi.fn()
    const { scheduleAutoUpdate } = await importModule()
    scheduleAutoUpdate(apply)

    await vi.advanceTimersByTimeAsync(35_000)
    expect(apply).toHaveBeenCalledOnce()
  })

  it('defers while a modal dialog is open, then applies after it closes', async () => {
    const dialog = document.createElement('dialog')
    dialog.setAttribute('open', '')
    document.body.appendChild(dialog)

    const apply = vi.fn()
    const { scheduleAutoUpdate } = await importModule()
    scheduleAutoUpdate(apply)

    await vi.advanceTimersByTimeAsync(60_000)
    expect(apply).not.toHaveBeenCalled()

    dialog.removeAttribute('open')
    await vi.advanceTimersByTimeAsync(10_000)
    expect(apply).toHaveBeenCalledOnce()
  })

  it('tracks whether an update is pending', async () => {
    const { scheduleAutoUpdate, hasPendingUpdate } = await importModule()
    expect(hasPendingUpdate()).toBe(false)

    scheduleAutoUpdate(vi.fn())
    expect(hasPendingUpdate()).toBe(true)

    setVisibility('hidden')
    document.dispatchEvent(new Event('visibilitychange'))
    expect(hasPendingUpdate()).toBe(false)
  })

  it('applyPendingUpdate applies with the target URL and consumes the update', async () => {
    const apply = vi.fn()
    const { scheduleAutoUpdate, applyPendingUpdate } = await importModule()
    scheduleAutoUpdate(apply)

    applyPendingUpdate('/events/42')
    expect(apply).toHaveBeenCalledExactlyOnceWith('/events/42')

    // Already applied — a later quiet moment must not apply again
    await vi.advanceTimersByTimeAsync(60_000)
    expect(apply).toHaveBeenCalledOnce()
  })

  it('forceUpdateNow applies a pending update immediately', async () => {
    const apply = vi.fn()
    const { scheduleAutoUpdate, forceUpdateNow, hasPendingUpdate } =
      await importModule()
    scheduleAutoUpdate(apply)
    expect(apply).not.toHaveBeenCalled()

    forceUpdateNow()

    expect(apply).toHaveBeenCalledExactlyOnceWith(undefined)
    expect(hasPendingUpdate()).toBe(false)
  })

  it('forceUpdateNow makes an update that arrives later apply immediately', async () => {
    const apply = vi.fn()
    const { scheduleAutoUpdate, forceUpdateNow } = await importModule()

    forceUpdateNow() // nothing pending yet — arms the force flag

    scheduleAutoUpdate(apply) // tab visible, no quiet moment
    expect(apply).toHaveBeenCalledExactlyOnceWith(undefined)
  })

  it('a second scheduled update replaces the first and applies once', async () => {
    const first = vi.fn()
    const second = vi.fn()
    const { scheduleAutoUpdate } = await importModule()

    scheduleAutoUpdate(first)
    scheduleAutoUpdate(second)

    setVisibility('hidden')
    document.dispatchEvent(new Event('visibilitychange'))
    expect(first).not.toHaveBeenCalled()
    expect(second).toHaveBeenCalledOnce()
  })
})
