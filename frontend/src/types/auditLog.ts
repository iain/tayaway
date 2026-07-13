// Audit log entries are deliberately NOT pool objects: they are append-only,
// unbounded in number, and owner-only, so they never sync over the WebSocket
// or hydrate the object pool. The audit log page fetches them page-by-page
// via rawApi.
export interface AuditLogEntry {
  id: string
  createdAt: string
  actorKind: 'user' | 'system'
  actorUserId: string | null
  // Resolved server-side at read time; null for system actors and for
  // users whose account has since been deleted.
  actorName: string | null
  service: string
  subjectType: string | null
  subjectId: string | null
  outcome: 'success' | 'denied' | 'error'
  errorCode: string | null
  errorMessage: string | null
  actionParams: Record<string, unknown>
  requestId: string | null
  idempotencyKeyHash: string | null
}

export interface AuditLogPage {
  entries: AuditLogEntry[]
  // Opaque keyset cursor for the next (older) page; null on the last page.
  nextCursor: string | null
}
