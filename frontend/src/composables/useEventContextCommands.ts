import { computed, watchEffect, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  ArrowDownTrayIcon,
  CalendarDaysIcon,
  ClipboardDocumentListIcon,
  CurrencyEuroIcon,
  EyeSlashIcon,
  HandThumbUpIcon,
  PlusIcon,
  UserGroupIcon,
  UsersIcon,
  ViewColumnsIcon,
} from '@heroicons/vue/24/outline'
import { useObjectPoolStore } from '@/stores/objectPool'
import {
  useCommandPalette,
  type ContextAction,
} from '@/composables/useCommandPalette'
import { useDateRangeActions } from '@/composables/useDateRangeActions'
import { useExpenseActions } from '@/composables/useExpenseActions'
import { useFocusedEvent } from '@/composables/useFocusedEvent'
import { isPollActive } from '@/utils/poll'
import { eventHasDates } from '@/utils/event'
import { generateIcs, downloadIcs } from '@/utils/ics'

const eventDetailRoutes = new Set([
  'event',
  'event-planning',
  'event-planning-vote',
  'event-planning-date-ranges',
  'event-rsvp',
  'event-days',
  'event-expenses',
  'event-chores',
])

export function useEventContextCommands() {
  const route = useRoute()
  const router = useRouter()
  const pool = useObjectPoolStore()
  const { setContext } = useCommandPalette()
  const { triggerAdd: triggerAddDateRange } = useDateRangeActions()
  const { triggerAdd: triggerAddExpense } = useExpenseActions()
  const { focusedEvent, focusCandidates, pinEvent, unfocusEvent } =
    useFocusedEvent()

  // The same event the subheader names: the URL's when you're inside one, the
  // focused one otherwise. Without the fallback the palette went silent about
  // the event on exactly the workspace pages the bar had started announcing it
  // on — the chrome claiming a context the palette denied. No route
  // suppression here: the bar hides itself on /events because it competes with
  // the list underneath, which a search surface never does.
  const contextEvent = computed(() => {
    const routeName = route.name as string
    const eventId = route.params?.id as string | undefined
    if (eventId && eventDetailRoutes.has(routeName)) {
      return pool.get('event', eventId) ?? null
    } else {
      return focusedEvent.value
    }
  })

  const contextActions = computed<ContextAction[]>(() => {
    const routeName = route.name as string
    const event = contextEvent.value
    if (!event) return []

    const eventId = event.id
    const poll = event.datePollId
      ? pool.get('datePoll', event.datePollId)
      : null
    const pollActive = isPollActive(poll)
    const hasDates = eventHasDates(event)
    const actions: ContextAction[] = []

    if (routeName !== 'event') {
      actions.push({
        id: 'ctx-event-overview',
        name: `Go to ${event.name}`,
        icon: CalendarDaysIcon,
        href: `/events/${eventId}`,
      })
    }

    if (
      routeName !== 'event-planning' &&
      routeName !== 'event-planning-vote' &&
      routeName !== 'event-planning-date-ranges'
    ) {
      actions.push({
        id: 'ctx-event-planning',
        name: 'Go to Planning',
        icon: ViewColumnsIcon,
        href: `/events/${eventId}/planning`,
      })
    }

    if (routeName !== 'event-rsvp') {
      actions.push({
        id: 'ctx-event-rsvp',
        name: 'Go to RSVP',
        icon: UserGroupIcon,
        href: `/events/${eventId}/rsvp`,
      })
    }

    if (routeName !== 'event-days') {
      actions.push({
        id: 'ctx-event-days',
        name: 'Go to Days',
        icon: UsersIcon,
        href: `/events/${eventId}/days`,
      })
    }

    if (routeName !== 'event-expenses') {
      actions.push({
        id: 'ctx-event-expenses',
        name: 'Go to Expenses',
        icon: CurrencyEuroIcon,
        href: `/events/${eventId}/expenses`,
      })
    }

    if (routeName !== 'event-chores') {
      actions.push({
        id: 'ctx-event-chores',
        name: 'Go to Chores',
        icon: ClipboardDocumentListIcon,
        href: `/events/${eventId}/chores`,
      })
    }

    if (
      pollActive &&
      poll &&
      poll.dateRangeIds.length > 0 &&
      routeName !== 'event-planning-vote'
    ) {
      actions.push({
        id: 'ctx-event-vote',
        name: 'Vote on dates',
        icon: HandThumbUpIcon,
        href: `/events/${eventId}/planning/vote`,
      })
    }

    if (pollActive) {
      actions.push({
        id: 'ctx-event-date-ranges',
        name: 'Add date options',
        icon: PlusIcon,
        run: async () => {
          if (routeName !== 'event-planning-date-ranges') {
            await router.push(`/events/${eventId}/planning/date-ranges`)
          }
          triggerAddDateRange()
        },
      })
    }

    if (hasDates) {
      actions.push({
        id: 'ctx-event-add-expense',
        name: 'Add expense',
        icon: CurrencyEuroIcon,
        run: async () => {
          if (routeName !== 'event-expenses') {
            await router.push(`/events/${eventId}/expenses`)
          }
          triggerAddExpense()
        },
      })
    }

    if (hasDates) {
      actions.push({
        id: 'ctx-event-download-ics',
        name: 'Download calendar file',
        icon: ArrowDownTrayIcon,
        run: () => {
          const ics = generateIcs({
            uid: event.id,
            summary: event.name,
            description: event.description,
            startDate: event.startDate,
            endDate: event.endDate,
            location: event.locationName,
            createdAt: event.createdAt,
          })
          downloadIcs(`${event.name}.ics`, ics)
        },
      })
    }

    return actions
  })

  // Moving focus was previously only possible through the chevron in the event
  // bar, or as a side effect of navigating into an event — so from a workspace
  // page you had to leave where you were to change what the page was about.
  // These do it in place, the way switching workspace already does.
  const focusActions = computed<ContextAction[]>(() => {
    const actions: ContextAction[] = focusCandidates.value
      .filter((candidate) => candidate.id !== focusedEvent.value?.id)
      .map((candidate) => ({
        id: `focus-${candidate.id}`,
        name: `Focus ${candidate.name}`,
        icon: CalendarDaysIcon,
        run: () => pinEvent(candidate.id),
      }))

    if (focusedEvent.value) {
      actions.push({
        id: 'unfocus-event',
        name: `Unfocus ${focusedEvent.value.name}`,
        icon: EyeSlashIcon,
        run: unfocusEvent,
      })
    }

    return actions
  })

  watchEffect(() => {
    setContext('event', {
      label: contextEvent.value?.name ?? 'Event',
      actions: contextActions.value,
    })
    setContext('focus', { label: 'Focus', actions: focusActions.value })
  })

  onUnmounted(() => {
    setContext('event', null)
    setContext('focus', null)
  })
}
