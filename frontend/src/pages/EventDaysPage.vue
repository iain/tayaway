<script setup lang="ts">
import { computed, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { storeToRefs } from 'pinia'
import {
  ArrowRightEndOnRectangleIcon,
  ArrowRightStartOnRectangleIcon,
  CalendarDaysIcon,
  ClockIcon,
  UsersIcon,
} from '@heroicons/vue/24/outline'
import { useAuthStore } from '@/stores/auth'
import { useHydratedEvent } from '@/composables/useHydratedEvent'
import { useMinuteTicker } from '@/composables/useMinuteTicker'
import { useObjectPoolStore } from '@/stores/objectPool'
import { api } from '@/api/client'
import PageHeader from '@/components/common/PageHeader.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import { daySummaries } from '@/utils/days'
import { eventHasDates } from '@/utils/event'
import { isPollActive } from '@/utils/poll'
import { formatDayHeader } from '@/utils/date'
import { zonedDateString } from '@/utils/timezone'
import { assignmentPerson } from '@/utils/chores'
import type {
  PoolApiResponse,
  PoolChore,
  PoolChoreAssignment,
  PoolMember,
} from '@/types/pool'
import type { HydratedAttendance } from '@/composables/useHydratedEvent'

const route = useRoute()
const eventId = computed(() => route.params.id as string)
const { event } = useHydratedEvent(eventId)

const authStore = useAuthStore()
const { currentUserId } = storeToRefs(authStore)
const pool = useObjectPoolStore()

const days = computed(() =>
  event.value ? daySummaries(event.value.attendances, event.value) : []
)

const anyoneComing = computed(() => days.value.some((d) => d.headcount > 0))
const peakHeadcount = computed(() =>
  Math.max(...days.value.map((d) => d.headcount), 0)
)

// The event-zone date, ticking while the page stays open, so the Today badge
// and the muted history agree with the chores pages on what "today" means.
const { now } = useMinuteTicker()
const today = computed(() =>
  event.value ? zonedDateString(now.value, event.value.timezone) : ''
)

const memberMap = computed(() => {
  const map = new Map<string, string>()
  for (const m of pool.getAll('member')) {
    map.set(m.userId, m.name || m.email || 'Unknown')
  }
  return map
})

function names(userIds: string[]): string {
  return userIds
    .map((id) => {
      const name = memberMap.value.get(id) ?? 'Unknown'
      return id === currentUserId.value ? `${name} (you)` : name
    })
    .sort((a, b) => a.localeCompare(b))
    .join(', ')
}

// Members who haven't responded at all — every count below is a lower bound
// until they do.
const pendingCount = computed(() => {
  if (!event.value?.workspace) return 0
  const respondedIds = new Set(
    event.value.attendances
      .filter((a) => a.userId && a.status !== 'pending')
      .map((a) => a.userId)
  )
  return event.value.workspace.members.filter(
    (m) => !respondedIds.has(m.userId)
  ).length
})

// That day's chore duties, so the cook sees their headcount in one glance.
const roster = computed(() =>
  pool.getAll('choreRoster').find((r) => r.eventId === eventId.value)
)

const chores = computed(() => {
  if (!roster.value) return []
  return pool
    .getAll('chore')
    .filter((c) => c.choreRosterId === roster.value!.id)
    .sort((a, b) => a.position - b.position)
})

const assigneesByChoreDate = computed(() => {
  const choreIds = new Set(chores.value.map((c) => c.id))
  const map = new Map<string, PoolChoreAssignment[]>()
  for (const a of pool.getAll('choreAssignment')) {
    if (!choreIds.has(a.choreId)) continue
    const key = `${a.choreId}|${a.date}`
    const list = map.get(key)
    if (list) list.push(a)
    else map.set(key, [a])
  }
  return map
})

const attendanceById = computed(() => {
  const map = new Map<string, HydratedAttendance>()
  for (const a of event.value?.attendances ?? []) map.set(a.id, a)
  return map
})

const memberByUserId = computed(() => {
  const map = new Map<string, PoolMember>()
  for (const m of pool.getAll('member')) map.set(m.userId, m)
  return map
})

// Duty holders resolve through their attendance's attendee, so guest
// assignments show the guest's name; "(you)" mirrors names() below.
function dutyNames(assignments: PoolChoreAssignment[]): string {
  return assignments
    .map((a) => {
      const person = assignmentPerson(
        a,
        attendanceById.value,
        memberByUserId.value
      )
      return person.userId === currentUserId.value
        ? `${person.name} (you)`
        : person.name
    })
    .sort((a, b) => a.localeCompare(b))
    .join(', ')
}

function dutiesFor(date: string): { chore: PoolChore; names: string }[] {
  const duties: { chore: PoolChore; names: string }[] = []
  for (const chore of chores.value) {
    const assignments = assigneesByChoreDate.value.get(`${chore.id}|${date}`)
    if (assignments) duties.push({ chore, names: dutyNames(assignments) })
  }
  return duties
}

function headcountMeta(day: {
  userIds: string[]
  guests: number
}): string | null {
  if (day.guests === 0) return null
  return `${day.userIds.length} + ${day.guests} guest${day.guests === 1 ? '' : 's'}`
}

// Land the user on today mid-event — the day they came to check. Guarded so
// it degrades to a no-op under jsdom and honors reduced-motion.
onMounted(() => {
  const target = document.querySelector<HTMLElement>(
    `[data-date="${today.value}"]`
  )
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches
  target?.scrollIntoView?.({
    block: 'start',
    behavior: reduce ? 'auto' : 'smooth',
  })
})

onMounted(async () => {
  const fetches: Promise<unknown>[] = [
    api.get<PoolApiResponse>(`/events/${eventId.value}/attendances`),
  ]
  const existingRoster = pool
    .getAll('choreRoster')
    .find((r) => r.eventId === eventId.value)
  if (existingRoster) {
    fetches.push(
      api.get<PoolApiResponse>(`/chore-rosters/${existingRoster.id}`)
    )
  }
  await Promise.all(fetches)
})
</script>

<template>
  <div>
    <div v-if="!event" class="text-ink-muted">Event not found</div>

    <div v-else>
      <PageHeader title="Days" size="sm" :icon="UsersIcon">
        <template #subtitle>
          Who's there each day — headcount, comings and goings, and chores.
        </template>
      </PageHeader>

      <!-- Poll still active: no dates to break into days yet -->
      <EmptyState
        v-if="isPollActive(event.datePoll)"
        :icon="ClockIcon"
        heading="Voting in progress"
        description="A date poll is open and members are voting. The day-by-day view will appear once dates are confirmed."
      >
        <router-link
          :to="`/events/${event.id}/planning`"
          class="text-sm text-cyan-700 hover:text-cyan-800 dark:text-cyan-400 dark:hover:text-cyan-300"
        >
          Go to Planning
        </router-link>
      </EmptyState>

      <template v-else-if="eventHasDates(event)">
        <!-- Nobody has RSVP'd yes yet: nothing meaningful to break down -->
        <EmptyState
          v-if="!anyoneComing"
          :icon="UsersIcon"
          heading="No attendees yet"
          description="Once people RSVP, you'll see who's around on each day."
        >
          <router-link
            :to="`/events/${event.id}/rsvp`"
            class="text-sm text-cyan-700 hover:text-cyan-800 dark:text-cyan-400 dark:hover:text-cyan-300"
          >
            Go to RSVP
          </router-link>
        </EmptyState>

        <template v-else>
          <p
            v-if="pendingCount > 0"
            data-testid="days-pending-note"
            class="text-ink-muted mb-4 text-sm"
          >
            {{ pendingCount }}
            {{ pendingCount === 1 ? 'member hasn’t' : 'members haven’t' }}
            responded yet, so counts may still grow.
            <router-link
              :to="`/events/${event.id}/rsvp`"
              class="text-cyan-700 hover:text-cyan-800 dark:text-cyan-400 dark:hover:text-cyan-300"
            >
              Go to RSVP
            </router-link>
          </p>

          <div
            data-testid="days-list"
            class="border-line bg-surface divide-line-faint divide-y overflow-hidden rounded-lg border"
          >
            <!-- Past days stay visible as the record of who was around, but
                 muted so the live part reads apart from history. -->
            <section
              v-for="(day, i) in days"
              :key="day.date"
              :data-date="day.date"
              class="scroll-mt-20"
              :class="day.date < today ? 'opacity-60' : ''"
            >
              <header
                class="bg-surface-sunken flex items-center justify-between gap-2 px-4 py-2"
              >
                <div class="flex items-center gap-2">
                  <h2
                    class="text-label"
                    :class="
                      day.date === today
                        ? 'text-ink font-semibold'
                        : 'text-ink-muted'
                    "
                  >
                    {{ formatDayHeader(day.date) }}
                  </h2>
                  <span
                    v-if="day.date === today"
                    class="bg-ink text-surface rounded-full px-2 py-0.5 text-xs font-medium"
                  >
                    Today
                  </span>
                </div>
                <div
                  class="flex items-baseline gap-1.5"
                  :data-testid="`days-headcount-${day.date}`"
                >
                  <span class="text-ink text-lg font-semibold tabular-nums">
                    {{ day.headcount }}
                  </span>
                  <span class="text-ink-muted text-meta">
                    {{
                      headcountMeta(day) ??
                      (day.headcount === 1 ? 'person' : 'people')
                    }}
                  </span>
                </div>
              </header>

              <div class="space-y-2 px-4 py-3">
                <!-- Peak-day meter: decorative echo of the headcount number -->
                <div
                  class="bg-surface-sunken h-1.5 overflow-hidden rounded-full"
                  aria-hidden="true"
                >
                  <div
                    class="h-full rounded-full bg-amber-400 dark:bg-amber-500"
                    :style="{
                      width: `${peakHeadcount ? (day.headcount / peakHeadcount) * 100 : 0}%`,
                    }"
                  />
                </div>

                <p
                  v-if="day.userIds.length === 0"
                  class="text-ink-muted text-sm italic"
                >
                  No one yet
                </p>
                <p v-else class="text-ink text-sm">{{ names(day.userIds) }}</p>

                <p
                  v-if="i > 0 && day.arrivals.length > 0"
                  class="text-state-success-ink flex items-start gap-1.5 text-sm"
                  :data-testid="`days-arrivals-${day.date}`"
                >
                  <ArrowRightEndOnRectangleIcon
                    class="mt-0.5 size-4 shrink-0"
                    aria-hidden="true"
                  />
                  <span>Arriving: {{ names(day.arrivals) }}</span>
                </p>
                <p
                  v-if="i < days.length - 1 && day.departures.length > 0"
                  class="text-ink-muted flex items-start gap-1.5 text-sm"
                  :data-testid="`days-departures-${day.date}`"
                >
                  <ArrowRightStartOnRectangleIcon
                    class="mt-0.5 size-4 shrink-0"
                    aria-hidden="true"
                  />
                  <span>Last day for {{ names(day.departures) }}</span>
                </p>

                <ul v-if="dutiesFor(day.date).length > 0" class="space-y-1">
                  <li
                    v-for="duty in dutiesFor(day.date)"
                    :key="duty.chore.id"
                    class="text-meta text-ink-muted"
                  >
                    <span class="text-ink font-medium">{{
                      duty.chore.name
                    }}</span>
                    <span v-if="duty.chore.time"> · {{ duty.chore.time }}</span>
                    — {{ duty.names }}
                  </li>
                </ul>
              </div>
            </section>
          </div>
        </template>
      </template>

      <!-- No dates yet -->
      <EmptyState
        v-else
        :icon="CalendarDaysIcon"
        heading="No dates confirmed yet"
        description="Once the event dates have been decided, you'll see who's around on each day."
      >
        <router-link
          :to="`/events/${event.id}/planning`"
          class="text-sm text-cyan-700 hover:text-cyan-800 dark:text-cyan-400 dark:hover:text-cyan-300"
        >
          Go to Planning
        </router-link>
      </EmptyState>
    </div>
  </div>
</template>
