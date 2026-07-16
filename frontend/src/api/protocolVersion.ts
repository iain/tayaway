/**
 * The client↔server protocol version this build speaks. Sent to the server
 * on every API request (`X-Client-Version` header, added in client.ts) and
 * on every WebSocket connect (`v` query param). The server rejects versions
 * below its `ClientProtocol::MIN_SUPPORTED_VERSION` — 426 over HTTP, an
 * `update_required` message over the WebSocket — and the client responds by
 * force-applying its pending service worker update (api/updateRequired.ts).
 *
 * Bump this when a change ships that older clients cannot survive (removed
 * endpoint, changed wire shape, ...). The server's minimum is raised only
 * later, once the fleet has updated — see doc/protocol-versioning.md.
 * This is NOT poolDb's CACHE_VERSION: that one versions this client's own
 * IndexedDB cache against its own code and moves far more often.
 *
 * Bump log:
 * - 1: versioning introduced; servers treat versionless clients as 0.
 * - 2: choreAssignment gained attendanceId and its userId became nullable —
 *   guest holders (userId: null) arrive once the server allows them; older
 *   clients render those as "?" and key their rosters off userId.
 */
export const PROTOCOL_VERSION = 2
