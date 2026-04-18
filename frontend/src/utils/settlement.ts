import { countDays } from '@/utils/event'

export interface PreviewTransfer {
  fromUserId: string
  toUserId: string
  amount: number
}

interface ExpenseLike {
  userId: string | null
  startDate: string
  endDate: string
  amount: number
  participantIds?: string[]
}

interface RsvpLike {
  userId: string
  startDate: string | null
  endDate: string | null
}

/**
 * Resolve an explicit expense participant to the user it refers to and the
 * factor (relative weight) it carries within the expense.
 */
type ParticipantResolver = (
  participantId: string
) => { userId: string; factor: number } | undefined

/**
 * Compute net balance for each user: fair share - amount paid.
 * Positive balance means user owes money; negative means user is owed.
 * Mirrors backend Settlements::Create#compute_balances.
 */
export function computeBalances(
  expenses: ExpenseLike[],
  rsvps: RsvpLike[],
  eventStartDate: string,
  eventEndDate: string,
  resolveParticipant?: ParticipantResolver
): Map<string, number> {
  const shareByUser = new Map<string, number>()
  const paidByUser = new Map<string, number>()

  const rsvpDates = rsvps.map((rsvp) => ({
    userId: rsvp.userId,
    startDate: rsvp.startDate ?? eventStartDate,
    endDate: rsvp.endDate ?? eventEndDate,
  }))

  for (const expense of expenses) {
    if (expense.userId) {
      paidByUser.set(
        expense.userId,
        (paidByUser.get(expense.userId) ?? 0) + expense.amount
      )
    }

    // Check for explicit participants
    const participantIds = expense.participantIds ?? []
    if (participantIds.length > 0 && resolveParticipant) {
      // Factor-weighted split among explicit participants
      const participants = participantIds
        .map((pid) => resolveParticipant(pid))
        .filter((p): p is { userId: string; factor: number } => p !== undefined)

      if (participants.length > 0) {
        const totalFactor = participants.reduce((s, p) => s + p.factor, 0)
        if (totalFactor > 0) {
          for (const p of participants) {
            const share = (p.factor / totalFactor) * expense.amount
            shareByUser.set(p.userId, (shareByUser.get(p.userId) ?? 0) + share)
          }
        }
        continue
      }
    }

    // RSVP overlap logic (default path)
    const overlaps: { userId: string; days: number }[] = []

    for (const rd of rsvpDates) {
      const overlapStart =
        expense.startDate > rd.startDate ? expense.startDate : rd.startDate
      const overlapEnd =
        expense.endDate < rd.endDate ? expense.endDate : rd.endDate

      if (overlapStart > overlapEnd) continue

      const days = countDays(overlapStart, overlapEnd)
      if (days > 0) {
        overlaps.push({ userId: rd.userId, days })
      }
    }

    const totalOverlapDays = overlaps.reduce((sum, o) => sum + o.days, 0)
    if (totalOverlapDays === 0) continue

    for (const { userId, days } of overlaps) {
      const share = (days / totalOverlapDays) * expense.amount
      shareByUser.set(userId, (shareByUser.get(userId) ?? 0) + share)
    }
  }

  const allUserIds = new Set([...shareByUser.keys(), ...paidByUser.keys()])
  const balances = new Map<string, number>()

  for (const uid of allUserIds) {
    const balance =
      Math.round(
        ((shareByUser.get(uid) ?? 0) - (paidByUser.get(uid) ?? 0)) * 100
      ) / 100
    if (Math.abs(balance) >= 0.005) {
      balances.set(uid, balance)
    }
  }

  return balances
}

/**
 * Greedy algorithm to minimize number of transfers.
 * Mirrors backend Settlements::Create#minimize_transfers.
 */
export function minimizeTransfers(
  balances: Map<string, number>
): PreviewTransfer[] {
  const debtors = [...balances.entries()]
    .filter(([, v]) => v > 0)
    .sort(([, a], [, b]) => b - a)
    .map(([k, v]) => ({ userId: k, amount: v }))

  const creditors = [...balances.entries()]
    .filter(([, v]) => v < 0)
    .sort(([, a], [, b]) => a - b)
    .map(([k, v]) => ({ userId: k, amount: -v }))

  const transfers: PreviewTransfer[] = []
  let dIdx = 0
  let cIdx = 0

  while (dIdx < debtors.length && cIdx < creditors.length) {
    const debtor = debtors[dIdx]!
    const creditor = creditors[cIdx]!
    const amount =
      Math.round(Math.min(debtor.amount, creditor.amount) * 100) / 100

    if (amount > 0.005) {
      transfers.push({
        fromUserId: debtor.userId,
        toUserId: creditor.userId,
        amount,
      })
    }

    debtor.amount = Math.round((debtor.amount - amount) * 100) / 100
    creditor.amount = Math.round((creditor.amount - amount) * 100) / 100

    if (debtor.amount < 0.005) dIdx++
    if (creditor.amount < 0.005) cIdx++
  }

  return transfers
}

/**
 * Derive net balances from a list of transfers.
 * For each user: balance = Σ(sent) − Σ(received).
 * Positive balance means user owes money; negative means user is owed.
 * Matches the sign convention used by computeBalances.
 */
export function deriveBalancesFromTransfers(
  transfers: Array<{
    fromUserId: string | null
    toUserId: string | null
    amount: number
  }>
): Map<string, number> {
  const balances = new Map<string, number>()

  for (const t of transfers) {
    if (t.fromUserId) {
      balances.set(t.fromUserId, (balances.get(t.fromUserId) ?? 0) + t.amount)
    }
    if (t.toUserId) {
      balances.set(t.toUserId, (balances.get(t.toUserId) ?? 0) - t.amount)
    }
  }

  for (const [userId, amount] of balances) {
    const rounded = Math.round(amount * 100) / 100
    if (Math.abs(rounded) < 0.005) {
      balances.delete(userId)
    } else {
      balances.set(userId, rounded)
    }
  }

  return balances
}
