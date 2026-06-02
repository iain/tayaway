// A scope is the partition this client's local pool/cache uses to organise
// data — `personal` for the cross-workspace stuff (notifications, workspace
// selector, own memberships) and `workspace:<id>` for everything else.
// Clearing a scope removes that scope from each object's set; only when an
// object's scope set becomes empty does the object itself go away.
//
// This is the client-side mirror of Topic on the backend: same wire shape
// for the workspace case, simplified to "personal" on the client because
// every scope on this client belongs to *this* user — naming it
// `user:<own-id>` would carry an id that's always implicit.
//
// Scope is a branded string: it serializes and compares like the wire
// form, slots into `Map<Scope, V>` and `Set<Scope>` without ceremony, but
// the compiler will not let an arbitrary string slip in where a Scope is
// expected. All construction goes through Scope.workspace / Scope.personal.

declare const SCOPE_BRAND: unique symbol

export type Scope = string & { readonly [SCOPE_BRAND]: never }

const WORKSPACE_PREFIX = 'workspace:'
const PERSONAL = 'personal'

export const Scope = {
  personal(): Scope {
    return PERSONAL as Scope
  },

  workspace(workspaceId: string): Scope {
    return `${WORKSPACE_PREFIX}${workspaceId}` as Scope
  },

  // Reify an externally-sourced string (IndexedDB meta key, test
  // fixture) into a Scope. Returns null for anything that doesn't match
  // the known shapes — keeps the parser honest about its contract.
  parse(raw: string): Scope | null {
    if (raw === PERSONAL) return raw as Scope
    if (
      raw.startsWith(WORKSPACE_PREFIX) &&
      raw.length > WORKSPACE_PREFIX.length
    ) {
      return raw as Scope
    }
    return null
  },

  isPersonal(scope: Scope): boolean {
    return scope === PERSONAL
  },

  isWorkspace(scope: Scope): boolean {
    return scope.startsWith(WORKSPACE_PREFIX)
  },

  // The workspace id this scope addresses, or null for the personal scope.
  workspaceId(scope: Scope): string | null {
    return scope.startsWith(WORKSPACE_PREFIX)
      ? scope.slice(WORKSPACE_PREFIX.length)
      : null
  },
} as const
