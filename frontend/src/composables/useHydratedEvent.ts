import { computed, type ComputedRef } from 'vue'
import { useObjectPoolStore } from '@/stores/objectPool'
import type {
  PoolEvent,
  PoolDateRange,
  PoolVote,
  PoolUser,
  PoolWorkspaceMembership,
  VoteResponse,
} from '@/types/pool'

// Hydrated types - these match the nested structure components expect
export interface HydratedVote {
  id: string
  dateRangeId: string
  userId: string
  user: PoolUser | undefined
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
  eventId: string
  startDate: string
  endDate: string
  votes: HydratedVote[]
  voteSummary: VoteSummary
}

export interface HydratedMember {
  id: string
  user: PoolUser | undefined
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
  userId: string
  user: PoolUser | undefined
  dateRanges: HydratedDateRange[]
  createdAt: string
  updatedAt: string
}

/**
 * Composable that provides a hydrated (denormalized) view of an event.
 *
 * This composable joins the normalized pool objects into the nested structure
 * that components expect, including user objects and vote summaries.
 *
 * @example
 * const { event, isLoading } = useHydratedEvent(eventId)
 * // event.value.dateRanges[0].votes[0].user - fully hydrated
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
  const user = pool.get('user', poolEvent.userId)
  const dateRanges = hydrateDateRanges(poolEvent.dateRangeIds, pool)
  const workspace = hydrateWorkspace(poolEvent.workspaceId, pool)

  return {
    id: poolEvent.id,
    name: poolEvent.name,
    description: poolEvent.description,
    workspaceId: poolEvent.workspaceId,
    workspace,
    userId: poolEvent.userId,
    user,
    dateRanges,
    createdAt: poolEvent.createdAt,
    updatedAt: poolEvent.updatedAt,
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

  const members = hydrateMembers(workspace.membershipIds, pool)

  return {
    id: workspace.id,
    name: workspace.name,
    members,
  }
}

/**
 * Hydrate workspace memberships into members with user objects.
 */
function hydrateMembers(
  membershipIds: string[],
  pool: ReturnType<typeof useObjectPoolStore>
): HydratedMember[] {
  return membershipIds
    .map((id) => pool.get('workspaceMembership', id))
    .filter((m): m is PoolWorkspaceMembership => m !== undefined)
    .map((membership) => ({
      id: membership.id,
      user: pool.get('user', membership.userId),
      role: membership.role,
    }))
}

/**
 * Hydrate date ranges with their votes.
 */
function hydrateDateRanges(
  dateRangeIds: string[],
  pool: ReturnType<typeof useObjectPoolStore>
): HydratedDateRange[] {
  return dateRangeIds
    .map((id) => pool.get('dateRange', id))
    .filter((dr): dr is PoolDateRange => dr !== undefined)
    .map((dr) => hydrateDateRange(dr, pool))
}

/**
 * Hydrate a single date range with its votes and summary.
 */
function hydrateDateRange(
  dateRange: PoolDateRange,
  pool: ReturnType<typeof useObjectPoolStore>
): HydratedDateRange {
  const votes = hydrateVotes(dateRange.voteIds, pool)
  const voteSummary = calculateVoteSummary(votes)

  return {
    id: dateRange.id,
    eventId: dateRange.eventId,
    startDate: dateRange.startDate,
    endDate: dateRange.endDate,
    votes,
    voteSummary,
  }
}

/**
 * Hydrate votes with their user objects.
 */
function hydrateVotes(
  voteIds: string[],
  pool: ReturnType<typeof useObjectPoolStore>
): HydratedVote[] {
  return voteIds
    .map((id) => pool.get('vote', id))
    .filter((v): v is PoolVote => v !== undefined)
    .map((vote) => ({
      id: vote.id,
      dateRangeId: vote.dateRangeId,
      userId: vote.userId,
      user: pool.get('user', vote.userId),
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
