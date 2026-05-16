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
    it('stringifies the workspace scope as workspace:<id>', () => {
      expect(String(Scope.workspace('abc'))).toBe('workspace:abc')
    })

    it('stringifies the personal scope as personal', () => {
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

    it('returns null for unknown shapes', () => {
      expect(Scope.parse('hadron:abc')).toBeNull()
      expect(Scope.parse('workspace:')).toBeNull()
      expect(Scope.parse('')).toBeNull()
    })
  })

  describe('use as a map key', () => {
    it('treats two workspace scopes with the same id as the same key', () => {
      const m = new Map<Scope, string>()
      m.set(Scope.workspace('abc'), 'one')
      m.set(Scope.workspace('abc'), 'two')
      expect(m.size).toBe(1)
      expect(m.get(Scope.workspace('abc'))).toBe('two')
    })

    it('distinguishes the personal scope from workspace scopes', () => {
      const m = new Map<Scope, string>()
      m.set(Scope.personal(), 'p')
      m.set(Scope.workspace('personal'), 'w') // pathological id; still distinct
      expect(m.get(Scope.personal())).toBe('p')
      expect(m.get(Scope.workspace('personal'))).toBe('w')
    })
  })
})
