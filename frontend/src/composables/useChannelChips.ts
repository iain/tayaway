export type ChannelKey = 'email' | 'in_app' | 'push'

export interface ChannelState {
  channel: ChannelKey
  enabled: boolean
  forced?: boolean
}

export interface KindState {
  key: string
  channels: ChannelState[]
}

export type ChipState =
  | { kind: 'hidden' }
  | { kind: 'forced'; enabled: boolean }
  | { kind: 'configurable'; enabled: boolean }

export interface ChipWrite {
  kindKey: string
  channel: ChannelKey
  enabled: boolean
}

function cellsFor(rows: KindState[], channel: ChannelKey): ChannelState[] {
  return rows.flatMap((row) => {
    const cell = row.channels.find((c) => c.channel === channel)
    return cell ? [cell] : []
  })
}

// Aggregate per-(kind, channel) state into a single chip decision for a
// category. If any row in the category forces the channel, the chip is
// forced too — even one forced row means the dispatcher will fire that
// channel regardless of preference, and a chip showing off would lie
// about what the user actually receives. Otherwise the chip aggregates
// configurable cells: on iff at least one is enabled.
export function chipState(rows: KindState[], channel: ChannelKey): ChipState {
  const cells = cellsFor(rows, channel)
  if (cells.length === 0) return { kind: 'hidden' }

  if (cells.some((c) => c.forced)) {
    return { kind: 'forced', enabled: true }
  }

  return {
    kind: 'configurable',
    enabled: cells.some((c) => c.enabled),
  }
}

export function chipWrites(
  rows: KindState[],
  channel: ChannelKey,
  target: boolean
): ChipWrite[] {
  return rows.flatMap((row) => {
    const cell = row.channels.find((c) => c.channel === channel)
    if (!cell || cell.forced || cell.enabled === target) return []
    return [{ kindKey: row.key, channel, enabled: target }]
  })
}
