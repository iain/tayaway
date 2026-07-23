import { computed, ref, type Ref } from 'vue'
import { useObjectPoolStore } from '@/stores/objectPool'
import { useWorkspaceStore } from '@/stores/workspace'
import type { ObjectTypeMap } from '@/types/pool'
import { addDays, localIsoDate } from '@/utils/date'
import { useEventsList } from './useEventsList'
import { useNow } from './useNow'
import { useOpenExpenses } from './useOpenExpenses'

// Backstop for the decay rule below. "Ended and settled" is a conjunction that
// a forgotten €3 expense can keep unsatisfied forever, and focus is exclusive
// — one abandoned event would otherwise hold it for good.
export const FOCUS_MAX_DAYS_AFTER_END = 30

// Which event each workspace is pinned to, and which one it has been told to
// stop showing. Personal, per-device UI state — it lives in localStorage
// rather than the shared pool, so putting your own attention on next summer's
// trip never moves anyone else's.
const PINNED_KEY = 'tayaway:focused-event'
const DISMISSED_KEY = 'tayaway:unfocused-event'

function load(key: string): Record<string, string> {
  try {
    const raw = localStorage.getItem(key)
    if (raw) {
      const parsed: unknown = JSON.parse(raw)
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        return parsed as Record<string, string>
      }
    }
  } catch {
    // Inaccessible or corrupted storage just falls back to derivation.
  }
  return {}
}

function save(key: string, value: Record<string, string>): void {
  try {
    localStorage.setItem(key, JSON.stringify(value))
  } catch {
    // Best effort — private mode or a full quota only loses stickiness.
  }
}

const pinnedByWorkspace = ref<Record<string, string>>(load(PINNED_KEY))

// Dismissal names the event it silenced rather than being a bare flag, so it
// expires on its own: "not this one, thanks", not "never again". Once the
// dismissed event stops being the one derivation would pick — it ended, or a
// nearer one came along — the bar comes back without the user remembering to
// undo anything.
const dismissedByWorkspace = ref<Record<string, string>>(load(DISMISSED_KEY))

/**
 * The event the app is currently "in the mode of" — the one whose chores,
 * expenses and roster the workspace-level pages should be about, without the
 * user having to pick it again on every visit.
 */
export function useFocusedEvent(now: Ref<Date> = useNow().now) {
  const pool = useObjectPoolStore()
  const workspace = useWorkspaceStore()
  const { currentEvents, upcomingEvents, pastEvents, planningEvents } =
    useEventsList(now)
  const { hasOpenExpenses } = useOpenExpenses()

  const today = computed(() => localIsoDate(now.value))

  // An event stops being able to hold focus once the group is done with it:
  // it has ended *and* nobody owes anybody for it. Settling up is almost
  // always the last thing to happen, days or weeks after the trip, so this
  // carries focus through the whole expense-filing tail on its own — no
  // separate grace period needed.
  function holdsFocus(event: ObjectTypeMap['event']): boolean {
    if (event.endDate === null) {
      // Still being planned: no dates to have passed yet.
      return true
    } else if (event.endDate >= today.value) {
      return true
    } else if (today.value > addDays(event.endDate, FOCUS_MAX_DAYS_AFTER_END)) {
      return false
    } else {
      return hasOpenExpenses(event.id)
    }
  }

  const pinnedEvent = computed<ObjectTypeMap['event'] | null>(() => {
    const workspaceId = workspace.currentWorkspaceId
    if (!workspaceId) return null
    const eventId = pinnedByWorkspace.value[workspaceId]
    if (!eventId) return null
    const event = pool.get('event', eventId)
    if (!event || !holdsFocus(event)) return null
    return event
  })

  // Derivation order: what's under way beats what's next. Both lists arrive
  // sorted (soonest to end / soonest to start), so the head is the one the
  // group is most plausibly thinking about.
  const derivedEvent = computed<ObjectTypeMap['event'] | null>(
    () => currentEvents.value[0] ?? upcomingEvents.value[0] ?? null
  )

  const dismissedEventId = computed<string | null>(() => {
    const workspaceId = workspace.currentWorkspaceId
    if (!workspaceId) return null
    return dismissedByWorkspace.value[workspaceId] ?? null
  })

  const focusedEvent = computed<ObjectTypeMap['event'] | null>(() => {
    if (pinnedEvent.value) {
      return pinnedEvent.value
    } else if (derivedEvent.value?.id === dismissedEventId.value) {
      return null
    } else {
      return derivedEvent.value
    }
  })

  // What the switcher offers: everything still live enough to be worth
  // working in, in the order the group is likely to want it. Events too far
  // gone to hold focus are left out — offering them would only let the user
  // pick a focus that decays out from under them on the next render.
  const focusCandidates = computed<ObjectTypeMap['event'][]>(() => [
    ...currentEvents.value,
    ...upcomingEvents.value,
    ...pastEvents.value.filter(holdsFocus),
    ...planningEvents.value,
  ])

  function forget(
    store: Ref<Record<string, string>>,
    key: string,
    workspaceId: string
  ): void {
    const rest = { ...store.value }
    delete rest[workspaceId]
    store.value = rest
    save(key, rest)
  }

  function pinEvent(eventId: string): void {
    const workspaceId = workspace.currentWorkspaceId
    if (!workspaceId) return
    pinnedByWorkspace.value = {
      ...pinnedByWorkspace.value,
      [workspaceId]: eventId,
    }
    save(PINNED_KEY, pinnedByWorkspace.value)
    // Choosing an event is the answer to having dismissed one.
    forget(dismissedByWorkspace, DISMISSED_KEY, workspaceId)
  }

  /**
   * Put the app out of event mode: no bar, no event-scoped pages guessing.
   * Dismissing what *derivation* would land on rather than what is currently
   * focused is what makes this immediate — dropping a pin alone would just
   * hand focus to the next candidate, which is not what "unfocus" promises.
   */
  function unfocusEvent(): void {
    const workspaceId = workspace.currentWorkspaceId
    if (!workspaceId) return
    forget(pinnedByWorkspace, PINNED_KEY, workspaceId)
    const derived = derivedEvent.value
    if (derived) {
      dismissedByWorkspace.value = {
        ...dismissedByWorkspace.value,
        [workspaceId]: derived.id,
      }
      save(DISMISSED_KEY, dismissedByWorkspace.value)
    } else {
      forget(dismissedByWorkspace, DISMISSED_KEY, workspaceId)
    }
  }

  /** Back to pure derivation, as if the user had never chosen anything. */
  function resetFocus(): void {
    const workspaceId = workspace.currentWorkspaceId
    if (!workspaceId) return
    forget(pinnedByWorkspace, PINNED_KEY, workspaceId)
    forget(dismissedByWorkspace, DISMISSED_KEY, workspaceId)
  }

  return {
    focusedEvent,
    focusCandidates,
    pinEvent,
    unfocusEvent,
    resetFocus,
  }
}
