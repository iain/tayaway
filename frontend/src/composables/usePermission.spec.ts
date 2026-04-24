import { describe, it, expect } from 'vitest'
import { can, permissionReason, permissionUx } from './usePermission'
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

  describe('permissionUx', () => {
    it('returns enabled when allowed', () => {
      const permissions: Record<string, Permission> = {
        edit: { allowed: true },
      }
      expect(permissionUx(permissions, 'edit')).toEqual({ behavior: 'enabled' })
    })

    it('returns hidden for ownership reasons', () => {
      const permissions: Record<string, Permission> = {
        edit: { allowed: false, reason: 'not_owner' },
      }
      expect(permissionUx(permissions, 'edit')).toEqual({ behavior: 'hidden' })
    })

    it('returns hidden for creator reasons', () => {
      const permissions: Record<string, Permission> = {
        delete: { allowed: false, reason: 'not_creator' },
      }
      expect(permissionUx(permissions, 'delete')).toEqual({
        behavior: 'hidden',
      })
    })

    it('returns hidden for settled — revert is the path, not edit', () => {
      const permissions: Record<string, Permission> = {
        edit: { allowed: false, reason: 'settled' },
      }
      expect(permissionUx(permissions, 'edit')).toEqual({
        behavior: 'hidden',
      })
    })

    it('returns hidden for is_revert — reverts are immutable', () => {
      const permissions: Record<string, Permission> = {
        edit: { allowed: false, reason: 'is_revert' },
      }
      expect(permissionUx(permissions, 'edit')).toEqual({
        behavior: 'hidden',
      })
    })

    it('returns modal for has_expenses', () => {
      const permissions: Record<string, Permission> = {
        delete: { allowed: false, reason: 'has_expenses' },
      }
      const result = permissionUx(permissions, 'delete')
      expect(result.behavior).toBe('modal')
      expect('message' in result && result.message).toContain('expenses')
    })

    it('returns modal for not_recipient', () => {
      const permissions: Record<string, Permission> = {
        mark_paid: { allowed: false, reason: 'not_recipient' },
      }
      const result = permissionUx(permissions, 'mark_paid')
      expect(result.behavior).toBe('modal')
      expect('message' in result && result.message).toContain('receiving')
    })

    it('returns hidden when permissions undefined', () => {
      expect(permissionUx(undefined, 'edit')).toEqual({ behavior: 'hidden' })
    })

    it('falls back to disabled with raw reason for unknown reasons', () => {
      const permissions: Record<string, Permission> = {
        edit: { allowed: false, reason: 'some_future_reason' },
      }
      expect(permissionUx(permissions, 'edit')).toEqual({
        behavior: 'disabled',
        tooltip: 'some_future_reason',
      })
    })
  })
})
