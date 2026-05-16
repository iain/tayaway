import { describe, it, expect } from 'vitest'
import { Scope } from './scope'

describe('Scope', () => {
  describe('construction', () => {
    it('builds a workspace scope from an id', () => {
      const s = Scope.workspace('ws-1')
      expect(Scope.isWorkspace(s)).toBe(true)
      expect(Scope.isPersonal(s)).toBe(false)
      expect(Scope.workspaceId(s)).toBe('ws-1')
    })

    it('builds the personal scope', () => {
      const s = Scope.personal()
      expect(Scope.isPersonal(s)).toBe(true)
      expect(Scope.isWorkspace(s)).toBe(false)
      expect(Scope.workspaceId(s)).toBeNull()
    })
  })

  describe('wire format', () => {
    it('stringifies as kind:id for workspace and "personal" for personal', () => {
      expect(String(Scope.workspace('abc'))).toBe('workspace:abc')
      expect(String(Scope.personal())).toBe('personal')
    })

    it('serializes to JSON as a string', () => {
      expect(JSON.stringify(Scope.workspace('abc'))).toBe('"workspace:abc"')
      expect(JSON.stringify(Scope.personal())).toBe('"personal"')
    })
  })

  describe('parse', () => {
    it('round-trips a workspace scope', () => {
      const s = Scope.workspace('abc')
      expect(Scope.parse(String(s))).toBe(s)
    })

    it('round-trips the personal scope', () => {
      expect(Scope.parse('personal')).toBe(Scope.personal())
    })

    it.each(['hadron:abc', 'workspace:', ''])(
      'returns null for %p',
      (input) => {
        expect(Scope.parse(input)).toBeNull()
      }
    )
  })
})
