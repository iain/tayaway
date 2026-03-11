import { describe, it, expect } from 'vitest'
import { getInitials, getMemberName, getMemberNameFromMap } from './member'
import type { PoolMember } from '@/types/pool'

function makeMember(overrides: Partial<PoolMember> = {}): PoolMember {
  return {
    id: '1',
    objectType: 'member',
    userId: 'u1',
    workspaceId: 'w1',
    role: 'member',
    name: null,
    email: 'alice@example.com',
    phoneNumber: null,
    birthday: null,
    locationName: null,
    latitude: null,
    longitude: null,
    hasIban: false,
    updatedAt: '2024-01-01T00:00:00Z',
    ...overrides,
  } as PoolMember
}

describe('getInitials', () => {
  it('returns first+last initials for a two-word name', () => {
    expect(getInitials({ name: 'Alice Smith', email: 'a@example.com' })).toBe(
      'AS',
    )
  })

  it('returns first+last initials for a three-word name', () => {
    expect(
      getInitials({ name: 'Alice Marie Smith', email: 'a@example.com' }),
    ).toBe('AS')
  })

  it('returns single initial for a one-word name', () => {
    expect(getInitials({ name: 'Alice', email: 'a@example.com' })).toBe('A')
  })

  it('uppercases initials', () => {
    expect(getInitials({ name: 'alice smith', email: 'a@example.com' })).toBe(
      'AS',
    )
  })

  it('falls back to first letter of email when name is null', () => {
    expect(getInitials({ name: null, email: 'bob@example.com' })).toBe('B')
  })

  it('returns ? when both name and email are empty', () => {
    expect(getInitials({ name: null, email: '' })).toBe('?')
  })
})

describe('getMemberName', () => {
  const pool = {
    findBy: (
      _type: 'member',
      _field: 'userId',
      value: string,
    ): PoolMember | undefined => {
      if (value === 'u1') return makeMember({ userId: 'u1', name: 'Alice' })
      if (value === 'u2')
        return makeMember({ userId: 'u2', name: null, email: 'bob@example.com' })
      return undefined
    },
  }

  it('returns the member name when present', () => {
    expect(getMemberName('u1', pool)).toBe('Alice')
  })

  it('falls back to email when name is null', () => {
    expect(getMemberName('u2', pool)).toBe('bob@example.com')
  })

  it('returns Unknown when member is not found', () => {
    expect(getMemberName('unknown-id', pool)).toBe('Unknown')
  })

  it('returns Unknown when userId is null', () => {
    expect(getMemberName(null, pool)).toBe('Unknown')
  })
})

describe('getMemberNameFromMap', () => {
  const memberMap: Map<string, PoolMember> = new Map([
    ['u1', makeMember({ userId: 'u1', name: 'Alice' })],
    ['u2', makeMember({ userId: 'u2', name: null, email: 'bob@example.com' })],
    [
      'u3',
      makeMember({ userId: 'u3', name: null, email: 'carol@example.com' }),
    ],
  ])

  it('returns the member name when present', () => {
    expect(getMemberNameFromMap('u1', memberMap)).toBe('Alice')
  })

  it('falls back to email local part when name is null', () => {
    expect(getMemberNameFromMap('u2', memberMap)).toBe('bob')
  })

  it('returns ? when userId is not in the map', () => {
    expect(getMemberNameFromMap('unknown-id', memberMap)).toBe('?')
  })
})
