import type { Permission } from '@/types/pool'

type Permissions = Record<string, Permission | string[]> | undefined

export function can(permissions: Permissions, action: string): boolean {
  if (!permissions) return false
  const perm = permissions[action]
  if (!perm || Array.isArray(perm)) return false
  return perm.allowed
}

export function permissionReason(
  permissions: Permissions,
  action: string
): string | undefined {
  if (!permissions) return undefined
  const perm = permissions[action]
  if (!perm || Array.isArray(perm)) return undefined
  return perm.reason
}
