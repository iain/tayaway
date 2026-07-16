import { computed, type ComputedRef } from 'vue'
import { useObjectPoolStore } from '@/stores/objectPool'
import type {
  PoolAttendance,
  PoolDatePoll,
  PoolDateRange,
  PoolEvent,
  PoolGuest,
  PoolMember,
  PoolRsvp,
  PoolVote,
  PoolWorkspace,
} from '@/types/pool'

// Hydrated types extend pool types with joined/computed fields.
export type HydratedVote = PoolVote & {
  member: PoolMember | undefined
}

export interface VoteSummary {
  yes: number
  no: number
  preferably_not: number
  total: number
}

export type HydratedDateRange = PoolDateRange & {
  votes: HydratedVote[]
  voteSummary: VoteSummary
}

export type HydratedDatePoll = PoolDatePoll & {
  selectedDateRange: HydratedDateRange | undefined
  dateRanges: HydratedDateRange[]
}

export type HydratedMember = Pick<
  PoolMember,
  'id' | 'objectType' | 'userId' | 'email' | 'name' | 'role' | 'updatedAt'
>

export type HydratedWorkspace = PoolWorkspace & {
  members: HydratedMember[]
}

export type HydratedRsvp = PoolRsvp & {
  member: PoolMember | undefined
}

/**
 * The person behind an attendance row, resolved from the pool. This is the
 * single frontend reader of the userId XOR guestId union (doc/attendances.md
 * containment contract) — components consume resolved attendees and never
 * branch on guestId themselves.
 */
export interface HydratedAttendee {
  name: string
  isGuest: boolean
  /** The account holder this row's shares bill to: the member themselves,
   *  or the guest's host. */
  billingUserId: string | null
  /** Member rows: the member behind the row. */
  member: PoolMember | undefined
  /** Guest rows: the guest behind the row. */
  guest: PoolGuest | undefined
  /** Guest rows: the member who brings (and is billed for) them. */
  hostMember: PoolMember | undefined
}

export type HydratedAttendance = PoolAttendance & {
  attendee: HydratedAttendee
}

export type HydratedEvent = PoolEvent & {
  workspace: HydratedWorkspace | undefined
  member: PoolMember | undefined
  datePoll: HydratedDatePoll | null
  rsvps: HydratedRsvp[]
  attendances: HydratedAttendance[]
}

/**
 * Composable that provides a hydrated (denormalized) view of an event.
 *
 * This composable joins the normalized pool objects into the nested structure
 * that components expect, including member objects and vote summaries.
 *
 * @example
 * const { event, isLoading } = useHydratedEvent(eventId)
 * // event.value.datePoll?.dateRanges[0].votes[0].member - fully hydrated
 */
export function useHydratedEvent(eventId: ComputedRef<string> | string): {
  event: ComputedRef<HydratedEvent | undefined>
  isLoading: ComputedRef<boolean>
} {
  const pool = useObjectPoolStore()

  const resolvedId = computed(() =>
    typeof eventId === 'string' ? eventId : eventId.value
  )

  const event = computed((): HydratedEvent | undefined => {
    // Access per-type versions for scoped reactivity (only re-compute when relevant types change)
    const tv = pool.typeVersions
    void tv.get('event')
    void tv.get('datePoll')
    void tv.get('dateRange')
    void tv.get('vote')
    void tv.get('member')
    void tv.get('workspace')
    void tv.get('rsvp')
    void tv.get('attendance')
    void tv.get('guest')

    const poolEvent = pool.get('event', resolvedId.value)
    if (!poolEvent) return undefined

    return hydrateEvent(poolEvent, pool)
  })

  const isLoading = computed(() => {
    return pool.get('event', resolvedId.value) === undefined
  })

  return {
    event,
    isLoading,
  }
}

type Pool = ReturnType<typeof useObjectPoolStore>

/**
 * Build a member lookup by userId for O(1) access during hydration.
 */
function buildMemberIndex(pool: Pool): Map<string, PoolMember> {
  const index = new Map<string, PoolMember>()
  for (const m of pool.getAll('member')) {
    index.set(m.userId, m)
  }
  return index
}

/**
 * Hydrate a pool event into the full nested structure.
 * Builds indexes upfront to avoid repeated full-pool scans.
 */
function hydrateEvent(poolEvent: PoolEvent, pool: Pool): HydratedEvent {
  const memberIndex = buildMemberIndex(pool)
  const member = memberIndex.get(poolEvent.userId)

  const datePollObj = pool
    .getAll('datePoll')
    .find((dp) => dp.eventId === poolEvent.id)

  let datePoll = null
  if (datePollObj) {
    // Only build vote index when a poll exists — avoids scanning all votes for events without polls
    const votesByDateRange = new Map<string, PoolVote[]>()
    for (const v of pool.getAll('vote')) {
      const existing = votesByDateRange.get(v.dateRangeId)
      if (existing) {
        existing.push(v)
      } else {
        votesByDateRange.set(v.dateRangeId, [v])
      }
    }
    datePoll = hydrateDatePoll(
      datePollObj.id,
      pool,
      votesByDateRange,
      memberIndex
    )
  }
  const workspace = hydrateWorkspace(poolEvent.workspaceId, pool)
  const rsvps = hydrateRsvps(poolEvent.id, pool, memberIndex)
  const attendances = hydrateAttendances(poolEvent.id, pool, memberIndex)

  return {
    ...poolEvent,
    workspace,
    member,
    datePoll,
    rsvps,
    attendances,
  }
}

/**
 * Hydrate a date poll with its date ranges.
 */
function hydrateDatePoll(
  datePollId: string,
  pool: Pool,
  votesByDateRange: Map<string, ReturnType<Pool['getAll']>>,
  memberIndex: Map<string, PoolMember>
): HydratedDatePoll | null {
  const pollData = pool.get('datePoll', datePollId)
  if (!pollData) return null

  const dateRanges = pool
    .getAll('dateRange')
    .filter((dr) => dr.datePollId === datePollId)
    .sort((a, b) => a.startDate.localeCompare(b.startDate))
    .map((dr) => hydrateDateRange(dr, votesByDateRange, memberIndex))

  const selectedDateRange = pollData.selectedDateRangeId
    ? dateRanges.find((dr) => dr.id === pollData.selectedDateRangeId)
    : undefined

  return {
    ...pollData,
    selectedDateRange,
    dateRanges,
  }
}

/**
 * Hydrate a workspace with its members.
 */
function hydrateWorkspace(
  workspaceId: string,
  pool: Pool
): HydratedWorkspace | undefined {
  const workspace = pool.get('workspace', workspaceId)
  if (!workspace) return undefined

  const members: HydratedMember[] = pool
    .getAll('member')
    .filter((m) => m.workspaceId === workspaceId)

  return {
    ...workspace,
    members,
  }
}

/**
 * Hydrate a single date range with its votes and summary.
 * Uses pre-built vote index for O(1) lookup instead of scanning all votes.
 */
function hydrateDateRange(
  dateRange: PoolDateRange,
  votesByDateRange: Map<string, ReturnType<Pool['getAll']>>,
  memberIndex: Map<string, PoolMember>
): HydratedDateRange {
  const rawVotes = (votesByDateRange.get(dateRange.id) ?? []) as PoolVote[]

  const votes: HydratedVote[] = rawVotes.map((vote) => ({
    ...vote,
    member: memberIndex.get(vote.userId),
  }))

  const voteSummary = calculateVoteSummary(votes)

  return {
    ...dateRange,
    votes,
    voteSummary,
  }
}

/**
 * Hydrate RSVPs for an event. Uses pre-built member index.
 */
function hydrateRsvps(
  eventId: string,
  pool: Pool,
  memberIndex: Map<string, PoolMember>
): HydratedRsvp[] {
  return pool
    .getAll('rsvp')
    .filter((r) => r.eventId === eventId)
    .map((rsvp) => ({
      ...rsvp,
      member: memberIndex.get(rsvp.userId),
    }))
}

/**
 * Resolve one attendance row to its hydrated attendee — the single frontend
 * reader of the userId XOR guestId union (see the HydratedAttendee
 * containment note above). Exported for consumers that join attendances
 * outside a full event hydration (the chore roster, the days page).
 */
export function hydrateAttendee(
  attendance: PoolAttendance,
  memberIndex: Map<string, PoolMember>,
  pool: Pool
): HydratedAttendance {
  if (attendance.guestId) {
    const guest = pool.get('guest', attendance.guestId)
    const hostMember = attendance.hostUserId
      ? memberIndex.get(attendance.hostUserId)
      : undefined
    return {
      ...attendance,
      attendee: {
        name: guest?.name ?? 'Unknown guest',
        isGuest: true,
        billingUserId: attendance.hostUserId,
        member: undefined,
        guest,
        hostMember,
      },
    }
  }
  const member = attendance.userId
    ? memberIndex.get(attendance.userId)
    : undefined
  return {
    ...attendance,
    attendee: {
      name: member?.name || member?.email || 'Unknown',
      isGuest: false,
      billingUserId: attendance.userId,
      member,
      guest: undefined,
      hostMember: undefined,
    },
  }
}

/**
 * Hydrate attendances for an event, resolving each row to its attendee —
 * see the HydratedAttendee containment note above.
 */
function hydrateAttendances(
  eventId: string,
  pool: Pool,
  memberIndex: Map<string, PoolMember>
): HydratedAttendance[] {
  return pool
    .getAll('attendance')
    .filter((a) => a.eventId === eventId)
    .map((attendance) => hydrateAttendee(attendance, memberIndex, pool))
}

/**
 * One event's attendances with resolved attendees, without the full event
 * hydration — for views that only join people (chore roster, days page).
 */
export function useHydratedAttendances(
  eventId: ComputedRef<string> | string
): ComputedRef<HydratedAttendance[]> {
  const pool = useObjectPoolStore()

  return computed(() => {
    const tv = pool.typeVersions
    void tv.get('attendance')
    void tv.get('guest')
    void tv.get('member')

    const id = typeof eventId === 'string' ? eventId : eventId.value
    return hydrateAttendances(id, pool, buildMemberIndex(pool))
  })
}

/**
 * Calculate vote summary from hydrated votes.
 */
function calculateVoteSummary(votes: HydratedVote[]): VoteSummary {
  let yes = 0
  let no = 0
  let preferably_not = 0
  for (const v of votes) {
    if (v.response === 'yes') yes++
    else if (v.response === 'no') no++
    else if (v.response === 'preferably_not') preferably_not++
  }
  return { yes, no, preferably_not, total: votes.length }
}
