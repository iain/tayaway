import { attendedDays, type AttendanceEntry } from '@/utils/event'

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
  attendance?: AttendanceEntry[] | null
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

  const rsvpDaySets = rsvps.map((rsvp) => ({
    userId: rsvp.userId,
    days: attendedDays(rsvp, eventStartDate, eventEndDate),
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

    // RSVP overlap logic (default path). Each attendee's share is proportional
    // to their head-days within the expense's own window: one attended day is
    // worth `1 + plusOnes` heads (the attendee plus any guests they bring that
    // day, absorbed by their host).
    const overlaps: { userId: string; heads: number }[] = []

    for (const rd of rsvpDaySets) {
      const heads = rd.days
        .filter((d) => d.date >= expense.startDate && d.date <= expense.endDate)
        .reduce((sum, d) => sum + 1 + d.plusOnes, 0)
      if (heads > 0) {
        overlaps.push({ userId: rd.userId, heads })
      }
    }

    const totalHeads = overlaps.reduce((sum, o) => sum + o.heads, 0)
    if (totalHeads === 0) continue

    for (const { userId, heads } of overlaps) {
      const share = (heads / totalHeads) * expense.amount
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

/**
 * Given the fair-share balances across all expenses in an event (using current
 * RSVPs) and the transfers already recorded by prior settlements in the chain,
 * return the residual per-user drift.
 *
 * drift[u] = currentBalance[u] − Σ(u sent) + Σ(u received) across prior transfers
 *
 * Positive drift means the user still owes; negative means they're still owed.
 * Values below the rounding threshold are dropped.
 */
export function computeDriftBalances(
  currentBalances: Map<string, number>,
  priorTransfers: Array<{
    fromUserId: string | null
    toUserId: string | null
    amount: number
  }>
): Map<string, number> {
  const alreadyMoved = deriveBalancesFromTransfers(priorTransfers)
  const drift = new Map(currentBalances)

  for (const [userId, amount] of alreadyMoved) {
    drift.set(userId, (drift.get(userId) ?? 0) - amount)
  }

  for (const [userId, amount] of [...drift.entries()]) {
    const rounded = Math.round(amount * 100) / 100
    if (Math.abs(rounded) < 0.005) drift.delete(userId)
    else drift.set(userId, rounded)
  }

  return drift
}

export interface AnnotatedTransfer {
  fromUserId: string | null
  toUserId: string | null
  amount: number
  annotation: string
}

/**
 * For each transfer, produce a human-readable "what this transfer did" string,
 * walking a simulated running balance so annotations reflect the effect of
 * prior transfers in the list.
 *
 * `nameFor` resolves a userId to a display name. Callers should pass a
 * fallback (e.g. "Unknown") for null/missing users.
 */
export function annotateTransfers(
  transfers: Array<{
    fromUserId: string | null
    toUserId: string | null
    amount: number
  }>,
  initialBalances: Map<string, number>,
  nameFor: (userId: string) => string
): AnnotatedTransfer[] {
  const running = new Map(initialBalances)
  const result: AnnotatedTransfer[] = []

  const EPS = 0.005

  for (const t of transfers) {
    const fromBalance = t.fromUserId ? (running.get(t.fromUserId) ?? 0) : 0
    const toBalance = t.toUserId ? (running.get(t.toUserId) ?? 0) : 0

    const fromName = t.fromUserId ? nameFor(t.fromUserId) : 'Unknown'
    const toName = t.toUserId ? nameFor(t.toUserId) : 'Unknown'

    const fromPhrase =
      Math.abs(fromBalance - t.amount) < EPS
        ? `Clears ${fromName}'s balance`
        : `Settles €${t.amount.toFixed(2)} of ${fromName}'s €${fromBalance.toFixed(2)}`

    const owedBefore = -toBalance
    const owedAfter = owedBefore - t.amount
    const toPhrase =
      Math.abs(owedAfter) < EPS
        ? `${toName} now even`
        : `${toName} still owed €${owedAfter.toFixed(2)}`

    result.push({
      fromUserId: t.fromUserId,
      toUserId: t.toUserId,
      amount: t.amount,
      annotation: `${fromPhrase} · ${toPhrase}`,
    })

    if (t.fromUserId) {
      running.set(
        t.fromUserId,
        Math.round((fromBalance - t.amount) * 100) / 100
      )
    }
    if (t.toUserId) {
      running.set(t.toUserId, Math.round((toBalance + t.amount) * 100) / 100)
    }
  }

  return result
}
