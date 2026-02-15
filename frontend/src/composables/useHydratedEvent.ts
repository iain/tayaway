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
  memberId: string
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
  email: string
  name: string | null
  role: string
}

export interface HydratedWorkspace {
  id: string
  name: string
  members: HydratedMember[]
}

export interface HydratedEvent {
  id: string
  name: string
  description: string | null
  workspaceId: string
  workspace: HydratedWorkspace | undefined
  memberId: string
  member: PoolMember | undefined
  datePoll: HydratedDatePoll | null
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

/**
 * Hydrate a pool event into the full nested structure.
 */
function hydrateEvent(
  poolEvent: PoolEvent,
  pool: ReturnType<typeof useObjectPoolStore>
): HydratedEvent {
  const member = pool.get('member', poolEvent.memberId)
  const datePollObj = pool
    .getAll('datePoll')
    .find((dp) => dp.eventId === poolEvent.id)
  const datePoll = datePollObj ? hydrateDatePoll(datePollObj.id, pool) : null
  const workspace = hydrateWorkspace(poolEvent.workspaceId, pool)

  return {
    id: poolEvent.id,
    name: poolEvent.name,
    description: poolEvent.description,
    workspaceId: poolEvent.workspaceId,
    workspace,
    memberId: poolEvent.memberId,
    member,
    datePoll,
    createdAt: poolEvent.createdAt,
    updatedAt: poolEvent.updatedAt,
  }
}

/**
 * Hydrate a date poll with its date ranges.
 */
function hydrateDatePoll(
  datePollId: string,
  pool: ReturnType<typeof useObjectPoolStore>
): HydratedDatePoll | null {
  const pollData = pool.get('datePoll', datePollId)
  if (!pollData) return null

  const dateRanges = hydrateDateRanges(pollData.id, pool)
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
  pool: ReturnType<typeof useObjectPoolStore>
): HydratedWorkspace | undefined {
  const workspace = pool.get('workspace', workspaceId)
  if (!workspace) return undefined

  const members = hydrateMembers(workspace.id, pool)

  return {
    id: workspace.id,
    name: workspace.name,
    members,
  }
}

/**
 * Hydrate workspace members directly from member pool objects.
 * No more user+membership join needed — member objects have everything.
 */
function hydrateMembers(
  workspaceId: string,
  pool: ReturnType<typeof useObjectPoolStore>
): HydratedMember[] {
  return pool
    .getAll('member')
    .filter((m) => m.workspaceId === workspaceId)
    .map((member) => ({
      id: member.id,
      email: member.email,
      name: member.name,
      role: member.role,
    }))
}

/**
 * Hydrate date ranges for a date poll.
 * Derives date range list from foreign key instead of explicit ID array.
 */
function hydrateDateRanges(
  datePollId: string,
  pool: ReturnType<typeof useObjectPoolStore>
): HydratedDateRange[] {
  return pool
    .getAll('dateRange')
    .filter((dr) => dr.datePollId === datePollId)
    .sort((a, b) => a.startDate.localeCompare(b.startDate))
    .map((dr) => hydrateDateRange(dr, pool))
}

/**
 * Hydrate a single date range with its votes and summary.
 */
function hydrateDateRange(
  dateRange: PoolDateRange,
  pool: ReturnType<typeof useObjectPoolStore>
): HydratedDateRange {
  const votes = hydrateVotes(dateRange.id, pool)
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
 * Hydrate votes for a date range.
 * Derives vote list from foreign key instead of explicit ID array.
 */
function hydrateVotes(
  dateRangeId: string,
  pool: ReturnType<typeof useObjectPoolStore>
): HydratedVote[] {
  return pool
    .getAll('vote')
    .filter((v) => v.dateRangeId === dateRangeId)
    .map((vote) => ({
      id: vote.id,
      dateRangeId: vote.dateRangeId,
      memberId: vote.memberId,
      member: pool.get('member', vote.memberId),
      response: vote.response,
      comment: vote.comment,
      createdAt: vote.createdAt,
      updatedAt: vote.updatedAt,
    }))
}

/**
 * Calculate vote summary from hydrated votes.
 */
function calculateVoteSummary(votes: HydratedVote[]): VoteSummary {
  return {
    yes: votes.filter((v) => v.response === 'yes').length,
    no: votes.filter((v) => v.response === 'no').length,
    preferably_not: votes.filter((v) => v.response === 'preferably_not').length,
    total: votes.length,
  }
}
