import { describe, it, expect } from 'vitest'
import { chipState, chipWrites } from './useChannelChips'
import type { KindState } from './useChannelChips'

function row(
  key: string,
  channels: Array<{
    channel: 'email' | 'in_app' | 'push'
    enabled: boolean
    forced?: boolean
  }>
): KindState {
  return { key, channels }
}

describe('chipState', () => {
  it('is hidden when no row defines the channel', () => {
    const rows = [row('a', [{ channel: 'email', enabled: false }])]
    expect(chipState(rows, 'push')).toEqual({ kind: 'hidden' })
  })

  it('is configurable + on when any configurable row has the channel enabled', () => {
    const rows = [
      row('a', [{ channel: 'email', enabled: true }]),
      row('b', [{ channel: 'email', enabled: false }]),
    ]
    expect(chipState(rows, 'email')).toEqual({
      kind: 'configurable',
      enabled: true,
    })
  })

  it('is configurable + off when all configurable rows are disabled', () => {
    const rows = [
      row('a', [{ channel: 'email', enabled: false }]),
      row('b', [{ channel: 'email', enabled: false }]),
    ]
    expect(chipState(rows, 'email')).toEqual({
      kind: 'configurable',
      enabled: false,
    })
  })

  it('is forced when every row that defines the channel is forced', () => {
    const rows = [
      row('new_session', [{ channel: 'email', enabled: true, forced: true }]),
      row('passkey_changed', [
        { channel: 'email', enabled: true, forced: true },
      ]),
    ]
    expect(chipState(rows, 'email')).toEqual({
      kind: 'forced',
      enabled: true,
    })
  })

  it('is forced when any row requires the channel, even if others are configurable', () => {
    const rows = [
      row('workspace_invite', [
        { channel: 'email', enabled: true, forced: true },
      ]),
      row('workspace_invite_accepted', [{ channel: 'email', enabled: false }]),
      row('member_role_changed', [{ channel: 'email', enabled: false }]),
    ]
    // Even one forced row means email will fire for the category, so the
    // chip can't honestly show off. Letting the user toggle the
    // configurable rows independently isn't possible from a category-
    // level chip — that's the trade-off of the simplified surface.
    expect(chipState(rows, 'email')).toEqual({
      kind: 'forced',
      enabled: true,
    })
  })
})

describe('chipWrites', () => {
  it('returns writes for every configurable row whose state would change', () => {
    const rows = [
      row('a', [{ channel: 'email', enabled: false }]),
      row('b', [{ channel: 'email', enabled: false }]),
    ]
    expect(chipWrites(rows, 'email', true)).toEqual([
      { kindKey: 'a', channel: 'email', enabled: true },
      { kindKey: 'b', channel: 'email', enabled: true },
    ])
  })

  it('skips configurable rows that already match the target', () => {
    const rows = [
      row('a', [{ channel: 'email', enabled: true }]),
      row('b', [{ channel: 'email', enabled: false }]),
    ]
    expect(chipWrites(rows, 'email', true)).toEqual([
      { kindKey: 'b', channel: 'email', enabled: true },
    ])
  })

  it('never writes to forced rows', () => {
    const rows = [
      row('forced_one', [{ channel: 'email', enabled: true, forced: true }]),
      row('configurable', [{ channel: 'email', enabled: false }]),
    ]
    expect(chipWrites(rows, 'email', false)).toEqual([])
    expect(chipWrites(rows, 'email', true)).toEqual([
      { kindKey: 'configurable', channel: 'email', enabled: true },
    ])
  })

  it('returns empty when nothing needs to change', () => {
    const rows = [
      row('a', [{ channel: 'email', enabled: true }]),
      row('b', [{ channel: 'email', enabled: true }]),
    ]
    expect(chipWrites(rows, 'email', true)).toEqual([])
  })
})
