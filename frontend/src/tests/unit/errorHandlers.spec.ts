import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import type { ComponentPublicInstance } from 'vue'

// The error handler logic extracted for testing. This mirrors what main.ts does
// so any changes to that handler should be reflected here.
function vueErrorHandler(
  err: unknown,
  instance: ComponentPublicInstance | null,
  info: string
): void {
  const componentName = instance?.$options?.name ?? 'anonymous'
  const props = instance?.$props ?? {}
  console.error('[Vue error]', { info, componentName, props }, err)
}

function unhandledRejectionHandler(event: PromiseRejectionEvent): void {
  console.error('[Unhandled rejection]', event.reason)
}

describe('vueErrorHandler', () => {
  let errorSpy: ReturnType<typeof vi.spyOn>

  beforeEach(() => {
    errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {})
  })

  afterEach(() => {
    errorSpy.mockRestore()
  })

  it('logs component name and props alongside the error and info', () => {
    const err = new Error('boom')
    const instance = {
      $options: { name: 'MyComponent' },
      $props: { eventId: 'evt-1', label: 'Test' },
    } as unknown as ComponentPublicInstance

    vueErrorHandler(err, instance, 'mounted hook')

    expect(errorSpy).toHaveBeenCalledWith(
      '[Vue error]',
      {
        info: 'mounted hook',
        componentName: 'MyComponent',
        props: { eventId: 'evt-1', label: 'Test' },
      },
      err
    )
  })

  it('falls back to "anonymous" when instance is null', () => {
    const err = new Error('no instance')

    vueErrorHandler(err, null, 'render function')

    expect(errorSpy).toHaveBeenCalledWith(
      '[Vue error]',
      { info: 'render function', componentName: 'anonymous', props: {} },
      err
    )
  })

  it('falls back to "anonymous" when component has no name', () => {
    const err = new Error('unnamed')
    const instance = {
      $options: {},
      $props: { foo: 'bar' },
    } as unknown as ComponentPublicInstance

    vueErrorHandler(err, instance, 'setup()')

    expect(errorSpy).toHaveBeenCalledWith(
      '[Vue error]',
      { info: 'setup()', componentName: 'anonymous', props: { foo: 'bar' } },
      err
    )
  })

  it('uses empty props when $props is not available', () => {
    const err = new Error('no props')
    const instance = {
      $options: { name: 'Bare' },
    } as unknown as ComponentPublicInstance

    vueErrorHandler(err, instance, 'watcher')

    expect(errorSpy).toHaveBeenCalledWith(
      '[Vue error]',
      { info: 'watcher', componentName: 'Bare', props: {} },
      err
    )
  })
})

describe('unhandledRejectionHandler', () => {
  let errorSpy: ReturnType<typeof vi.spyOn>

  beforeEach(() => {
    errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {})
  })

  afterEach(() => {
    errorSpy.mockRestore()
  })

  it('logs the rejection reason', () => {
    const reason = new Error('unhandled')
    const event = { reason } as PromiseRejectionEvent

    unhandledRejectionHandler(event)

    expect(errorSpy).toHaveBeenCalledWith('[Unhandled rejection]', reason)
  })
})
