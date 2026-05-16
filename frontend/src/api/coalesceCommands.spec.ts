import { describe, it, expect, vi } from 'vitest'
import type { StoredCommand } from './commandDb'
import { getResourceKey, coalesceCommands } from './coalesceCommands'

function cmd(
  overrides: Partial<StoredCommand> & Pick<StoredCommand, 'method' | 'path'>
): StoredCommand {
  return {
    id: crypto.randomUUID(),
    createdAt: Date.now(),
    ...overrides,
  }
}

describe('getResourceKey', () => {
  it('returns path for PUT', () => {
    expect(getResourceKey(cmd({ method: 'PUT', path: '/events/abc' }))).toBe(
      '/events/abc'
    )
  })

  it('returns path for PATCH', () => {
    expect(getResourceKey(cmd({ method: 'PATCH', path: '/events/abc' }))).toBe(
      '/events/abc'
    )
  })

  it('returns path for DELETE', () => {
    expect(getResourceKey(cmd({ method: 'DELETE', path: '/events/abc' }))).toBe(
      '/events/abc'
    )
  })

  it('returns projected path for POST with id in body', () => {
    expect(
      getResourceKey(
        cmd({
          method: 'POST',
          path: '/events',
          body: { id: 'abc', name: 'Test' },
        })
      )
    ).toBe('/events/abc')
  })

  it('returns null for POST without id in body', () => {
    expect(
      getResourceKey(
        cmd({ method: 'POST', path: '/events/x/poll/close', body: {} })
      )
    ).toBeNull()
  })

  it('returns null for POST with no body', () => {
    expect(
      getResourceKey(cmd({ method: 'POST', path: '/events/x/poll/reopen' }))
    ).toBeNull()
  })

  it('handles trailing slash in POST path', () => {
    expect(
      getResourceKey(
        cmd({ method: 'POST', path: '/events/', body: { id: 'abc' } })
      )
    ).toBe('/events/abc')
  })
})

describe('coalesceCommands', () => {
  it('POST + PUT → merged POST', () => {
    const commands = [
      cmd({
        method: 'POST',
        path: '/events',
        body: { id: 'abc', name: 'Party' },
      }),
      cmd({ method: 'PUT', path: '/events/abc', body: { name: 'Big Party' } }),
    ]

    const result = coalesceCommands(commands)

    expect(result).toHaveLength(1)
    expect(result[0]!.method).toBe('POST')
    expect(result[0]!.path).toBe('/events')
    expect(result[0]!.body).toEqual({ id: 'abc', name: 'Big Party' })
    expect(result[0]!.originalIds).toHaveLength(2)
  })

  it('POST + DELETE → cancellation (empty result)', () => {
    const commands = [
      cmd({
        method: 'POST',
        path: '/events',
        body: { id: 'abc', name: 'Party' },
      }),
      cmd({ method: 'DELETE', path: '/events/abc' }),
    ]

    const result = coalesceCommands(commands)

    expect(result).toHaveLength(0)
  })

  it('PUT + PUT → merged PUT', () => {
    const commands = [
      cmd({ method: 'PUT', path: '/events/abc', body: { name: 'Party' } }),
      cmd({
        method: 'PUT',
        path: '/events/abc',
        body: { description: 'Fun times' },
      }),
    ]

    const result = coalesceCommands(commands)

    expect(result).toHaveLength(1)
    expect(result[0]!.method).toBe('PUT')
    expect(result[0]!.body).toEqual({ name: 'Party', description: 'Fun times' })
    expect(result[0]!.originalIds).toHaveLength(2)
  })

  it('PUT + DELETE → DELETE only', () => {
    const commands = [
      cmd({ method: 'PUT', path: '/events/abc', body: { name: 'Party' } }),
      cmd({ method: 'DELETE', path: '/events/abc' }),
    ]

    const result = coalesceCommands(commands)

    expect(result).toHaveLength(1)
    expect(result[0]!.method).toBe('DELETE')
    expect(result[0]!.originalIds).toHaveLength(2)
  })

  it('DELETE + POST → both preserved in order', () => {
    const commands = [
      cmd({ method: 'DELETE', path: '/events/abc' }),
      cmd({
        method: 'POST',
        path: '/events',
        body: { id: 'abc', name: 'Recreated' },
      }),
    ]

    const result = coalesceCommands(commands)

    expect(result).toHaveLength(2)
    expect(result[0]!.method).toBe('DELETE')
    expect(result[1]!.method).toBe('POST')
  })

  it('DELETE + PUT → both preserved in order', () => {
    const commands = [
      cmd({ method: 'DELETE', path: '/events/abc' }),
      cmd({ method: 'PUT', path: '/events/abc', body: { name: 'Updated' } }),
    ]

    const result = coalesceCommands(commands)

    expect(result).toHaveLength(2)
    expect(result[0]!.method).toBe('DELETE')
    expect(result[1]!.method).toBe('PUT')
  })

  it('coalesces independently per resource key', () => {
    const commands = [
      cmd({ method: 'PUT', path: '/events/aaa', body: { name: 'A1' } }),
      cmd({ method: 'PUT', path: '/events/bbb', body: { name: 'B1' } }),
      cmd({ method: 'PUT', path: '/events/aaa', body: { name: 'A2' } }),
      cmd({
        method: 'PUT',
        path: '/events/bbb',
        body: { description: 'B desc' },
      }),
    ]

    const result = coalesceCommands(commands)

    expect(result).toHaveLength(2)
    expect(result[0]!.body).toEqual({ name: 'A2' })
    expect(result[1]!.body).toEqual({ name: 'B1', description: 'B desc' })
  })

  it('real-world chain: create + update + update + delete → empty', () => {
    const commands = [
      cmd({
        method: 'POST',
        path: '/events',
        body: { id: 'abc', name: 'Party' },
      }),
      cmd({ method: 'PUT', path: '/events/abc', body: { name: 'Big Party' } }),
      cmd({
        method: 'PUT',
        path: '/events/abc',
        body: { description: 'So fun' },
      }),
      cmd({ method: 'DELETE', path: '/events/abc' }),
    ]

    const result = coalesceCommands(commands)

    expect(result).toHaveLength(0)
  })

  it('real-world chain: 3 name changes → 1 PUT', () => {
    const commands = [
      cmd({ method: 'PUT', path: '/events/abc', body: { name: 'v1' } }),
      cmd({ method: 'PUT', path: '/events/abc', body: { name: 'v2' } }),
      cmd({ method: 'PUT', path: '/events/abc', body: { name: 'v3' } }),
    ]

    const result = coalesceCommands(commands)

    expect(result).toHaveLength(1)
    expect(result[0]!.body).toEqual({ name: 'v3' })
    expect(result[0]!.originalIds).toHaveLength(3)
  })

  it('non-coalescable commands pass through unchanged', () => {
    const commands = [
      cmd({ method: 'POST', path: '/events/x/poll/close', body: {} }),
      cmd({ method: 'POST', path: '/events/x/poll/reopen' }),
      cmd({
        method: 'POST',
        path: '/events/x/votes',
        body: { dateRangeId: 'dr1', response: 'yes' },
      }),
    ]

    const result = coalesceCommands(commands)

    expect(result).toHaveLength(3)
    expect(result[0]!.method).toBe('POST')
    expect(result[0]!.path).toBe('/events/x/poll/close')
    expect(result[1]!.method).toBe('POST')
    expect(result[1]!.path).toBe('/events/x/poll/reopen')
    expect(result[2]!.method).toBe('POST')
    expect(result[2]!.path).toBe('/events/x/votes')
  })

  it('originalIds tracking accumulates all source IDs', () => {
    const c1 = cmd({
      method: 'POST',
      path: '/events',
      body: { id: 'abc', name: 'v1' },
    })
    const c2 = cmd({ method: 'PUT', path: '/events/abc', body: { name: 'v2' } })
    const c3 = cmd({
      method: 'PUT',
      path: '/events/abc',
      body: { description: 'desc' },
    })

    const result = coalesceCommands([c1, c2, c3])

    expect(result).toHaveLength(1)
    expect(result[0]!.originalIds).toEqual([c1.id, c2.id, c3.id])
  })

  it('cancelled commands still track all original IDs', () => {
    const c1 = cmd({
      method: 'POST',
      path: '/events',
      body: { id: 'abc', name: 'Party' },
    })
    const c2 = cmd({
      method: 'PUT',
      path: '/events/abc',
      body: { name: 'Updated' },
    })
    const c3 = cmd({ method: 'DELETE', path: '/events/abc' })

    const result = coalesceCommands([c1, c2, c3])

    expect(result).toHaveLength(0)
  })

  it('preserves order of non-coalescable among coalescable', () => {
    const commands = [
      cmd({ method: 'PUT', path: '/events/abc', body: { name: 'v1' } }),
      cmd({ method: 'POST', path: '/events/abc/poll/close', body: {} }),
      cmd({ method: 'PUT', path: '/events/abc', body: { name: 'v2' } }),
    ]

    const result = coalesceCommands(commands)

    expect(result).toHaveLength(2)
    // The merged PUT should be at index 0 (where the first PUT was)
    expect(result[0]!.method).toBe('PUT')
    expect(result[0]!.body).toEqual({ name: 'v2' })
    // The non-coalescable POST should be at index 1
    expect(result[1]!.method).toBe('POST')
    expect(result[1]!.path).toBe('/events/abc/poll/close')
  })

  it('empty input returns empty output', () => {
    expect(coalesceCommands([])).toEqual([])
  })

  it('single command passes through', () => {
    const c = cmd({
      method: 'PUT',
      path: '/events/abc',
      body: { name: 'test' },
    })
    const result = coalesceCommands([c])

    expect(result).toHaveLength(1)
    expect(result[0]!.method).toBe('PUT')
    expect(result[0]!.originalIds).toEqual([c.id])
  })

  it('later field values override earlier ones in body merge', () => {
    const commands = [
      cmd({
        method: 'PUT',
        path: '/events/abc',
        body: { name: 'old', description: 'keep' },
      }),
      cmd({ method: 'PUT', path: '/events/abc', body: { name: 'new' } }),
    ]

    const result = coalesceCommands(commands)

    expect(result).toHaveLength(1)
    expect(result[0]!.body).toEqual({ name: 'new', description: 'keep' })
  })

  it('PATCH treated same as PUT for merging', () => {
    const commands = [
      cmd({ method: 'PATCH', path: '/events/abc', body: { name: 'v1' } }),
      cmd({
        method: 'PATCH',
        path: '/events/abc',
        body: { description: 'desc' },
      }),
    ]

    const result = coalesceCommands(commands)

    expect(result).toHaveLength(1)
    expect(result[0]!.method).toBe('PATCH')
    expect(result[0]!.body).toEqual({ name: 'v1', description: 'desc' })
  })

  describe('workspaceId reconciliation', () => {
    it('preserves the workspaceId of a single command', () => {
      const result = coalesceCommands([
        cmd({ method: 'PUT', path: '/events/abc', workspaceId: 'ws-1' }),
      ])

      expect(result[0]!.workspaceId).toBe('ws-1')
    })

    it('coerces a missing workspaceId to null', () => {
      const result = coalesceCommands([
        cmd({ method: 'PUT', path: '/events/abc' }),
      ])

      expect(result[0]!.workspaceId).toBeNull()
    })

    it('keeps the agreed workspaceId when merged commands match', () => {
      const result = coalesceCommands([
        cmd({
          method: 'POST',
          path: '/events',
          body: { id: 'abc' },
          workspaceId: 'ws-1',
        }),
        cmd({
          method: 'PUT',
          path: '/events/abc',
          body: { name: 'x' },
          workspaceId: 'ws-1',
        }),
      ])

      expect(result).toHaveLength(1)
      expect(result[0]!.workspaceId).toBe('ws-1')
    })

    // When commands disagree on workspaceId we surface undefined so the
    // replay falls back to the current workspace, and log loudly because
    // resource-keyed merges shouldn't naturally span workspaces.
    it('returns undefined and logs when merged commands disagree', () => {
      const consoleError = vi
        .spyOn(console, 'error')
        .mockImplementation(() => {})

      const result = coalesceCommands([
        cmd({
          method: 'PUT',
          path: '/events/abc',
          body: { name: 'a' },
          workspaceId: 'ws-1',
        }),
        cmd({
          method: 'PUT',
          path: '/events/abc',
          body: { name: 'b' },
          workspaceId: 'ws-2',
        }),
      ])

      expect(result[0]!.workspaceId).toBeUndefined()
      expect(consoleError).toHaveBeenCalledOnce()
      consoleError.mockRestore()
    })
  })
})
