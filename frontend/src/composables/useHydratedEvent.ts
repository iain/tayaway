import { computed, type ComputedRef } from 'vue'
import { useObjectPoolStore } from '@/stores/objectPool'
import type {
  PoolEvent,
  PoolDateRange,
  PoolMember,
  VoteResponse,
  DatePollStatus,
} from '@/types/pool'

// Hydrated types - these match the nested structure components expect
export interface HydratedVote {
  id: string
  dateRangeId: string
  userId: string
  member: PoolMember | undefined
  response: VoteResponse
  comment: string | null
  createdAt: string
  updatedAt: string
}

export interface VoteSummary {
  yes: number
  no: number
  preferably_not: number
  total: number
}

export interface HydratedDateRange {
  id: string
  datePollId: string
  startDate: string
  endDate: string
  votes: HydratedVote[]
  voteSummary: VoteSummary
}

export interface HydratedDatePoll {
  id: string
  eventId: string
  deadline: string
  status: DatePollStatus
  selectedDateRangeId: string | null
  selectedDateRange: HydratedDateRange | undefined
  closedAt: string | null
  dateRanges: HydratedDateRange[]
  createdAt: string
  updatedAt: string
}

export interface HydratedMember {
  id: string
  userId: string
  email: string
  name: string | null
  role: string
}

export interface HydratedWorkspace {
  id: string
  name: string
  members: HydratedMember[]
}

export interface HydratedRsvp {
  id: string
  eventId: string
  userId: string
  member: PoolMember | undefined
  attending: boolean
  startDate: string | null
  endDate: string | null
  createdAt: string
  updatedAt: string
}

export interface HydratedEvent {
  id: string
  name: string
  description: string | null
  startDate: string | null
  endDate: string | null
  locationName: string | null
  latitude: number | null
  longitude: number | null
  workspaceId: string
  workspace: HydratedWorkspace | undefined
  userId: string
  member: PoolMember | undefined
  datePoll: HydratedDatePoll | null
  rsvps: HydratedRsvp[]
  createdAt: string
  updatedAt: string
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
    // Access version to establish reactivity dependency on any pool change
    void pool.version

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

  // Build vote index by dateRangeId — avoids re-scanning all votes per date range
  const votesByDateRange = new Map<string, typeof votes>()
  const votes = pool.getAll('vote')
  for (const v of votes) {
    const existing = votesByDateRange.get(v.dateRangeId)
    if (existing) {
      existing.push(v)
    } else {
      votesByDateRange.set(v.dateRangeId, [v])
    }
  }

  const datePoll = datePollObj
    ? hydrateDatePoll(datePollObj.id, pool, votesByDateRange, memberIndex)
    : null
  const workspace = hydrateWorkspace(poolEvent.workspaceId, pool)
  const rsvps = hydrateRsvps(poolEvent.id, pool, memberIndex)

  return {
    id: poolEvent.id,
    name: poolEvent.name,
    description: poolEvent.description,
    startDate: poolEvent.startDate,
    endDate: poolEvent.endDate,
    locationName: poolEvent.locationName,
    latitude: poolEvent.latitude,
    longitude: poolEvent.longitude,
    workspaceId: poolEvent.workspaceId,
    workspace,
    userId: poolEvent.userId,
    member,
    datePoll,
    rsvps,
    createdAt: poolEvent.createdAt,
    updatedAt: poolEvent.updatedAt,
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
    id: pollData.id,
    eventId: pollData.eventId,
    deadline: pollData.deadline,
    status: pollData.status,
    selectedDateRangeId: pollData.selectedDateRangeId,
    selectedDateRange,
    closedAt: pollData.closedAt,
    dateRanges,
    createdAt: pollData.createdAt,
    updatedAt: pollData.updatedAt,
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

  const members = pool
    .getAll('member')
    .filter((m) => m.workspaceId === workspaceId)
    .map((member) => ({
      id: member.id,
      userId: member.userId,
      email: member.email,
      name: member.name,
      role: member.role,
    }))

  return {
    id: workspace.id,
    name: workspace.name,
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
  const rawVotes = (votesByDateRange.get(dateRange.id) ?? []) as Array<{
    id: string
    dateRangeId: string
    userId: string
    response: VoteResponse
    comment: string | null
    createdAt: string
    updatedAt: string
  }>

  const votes: HydratedVote[] = rawVotes.map((vote) => ({
    id: vote.id,
    dateRangeId: vote.dateRangeId,
    userId: vote.userId,
    member: memberIndex.get(vote.userId),
    response: vote.response,
    comment: vote.comment,
    createdAt: vote.createdAt,
    updatedAt: vote.updatedAt,
  }))

  const voteSummary = calculateVoteSummary(votes)

  return {
    id: dateRange.id,
    datePollId: dateRange.datePollId,
    startDate: dateRange.startDate,
    endDate: dateRange.endDate,
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
      id: rsvp.id,
      eventId: rsvp.eventId,
      userId: rsvp.userId,
      member: memberIndex.get(rsvp.userId),
      attending: rsvp.attending,
      startDate: rsvp.startDate,
      endDate: rsvp.endDate,
      createdAt: rsvp.createdAt,
      updatedAt: rsvp.updatedAt,
    }))
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
