import { describe, it, expect } from 'vitest'
import { can, permissionReason } from './usePermission'
import type { Permission } from '@/types/pool'

describe('usePermission', () => {
  describe('can', () => {
    it('returns true when permission is allowed', () => {
      const permissions: Record<string, Permission> = {
        edit: { allowed: true },
      }
      expect(can(permissions, 'edit')).toBe(true)
    })

    it('returns false when permission is denied', () => {
      const permissions: Record<string, Permission> = {
        edit: { allowed: false, reason: 'not_owner' },
      }
      expect(can(permissions, 'edit')).toBe(false)
    })

    it('returns false when permission key is missing', () => {
      const permissions: Record<string, Permission> = {}
      expect(can(permissions, 'edit')).toBe(false)
    })

    it('returns false when permissions is undefined', () => {
      expect(can(undefined, 'edit')).toBe(false)
    })
  })

  describe('permissionReason', () => {
    it('returns the reason when denied', () => {
      const permissions: Record<string, Permission> = {
        edit: { allowed: false, reason: 'not_owner' },
      }
      expect(permissionReason(permissions, 'edit')).toBe('not_owner')
    })

    it('returns undefined when allowed', () => {
      const permissions: Record<string, Permission> = {
        edit: { allowed: true },
      }
      expect(permissionReason(permissions, 'edit')).toBeUndefined()
    })

    it('returns undefined when missing', () => {
      expect(permissionReason(undefined, 'edit')).toBeUndefined()
    })
  })
})
