<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { CalendarDaysIcon } from '@heroicons/vue/24/outline'
import { eventHasDates } from '@/utils/event'
import DateRangeDisplay from '@/components/common/DateRangeDisplay.vue'
import type { PoolEvent } from '@/types/pool'

const props = defineProps<{
  event: PoolEvent
}>()

const route = useRoute()
const eventId = computed(() => route.params.id as string)

const activeTab = computed(() => {
  const name = route.name as string
  if (
    name === 'event-planning' ||
    name === 'event-planning-vote' ||
    name === 'event-planning-date-ranges'
  )
    return 'planning'
  if (name === 'event-rsvp') return 'rsvp'
  if (name === 'event-expenses') return 'expenses'
  if (name === 'event-chores') return 'chores'
  return null
})

function tabClass(active: boolean): string {
  return [
    'shrink-0 rounded-md px-3 py-1.5 text-sm font-medium whitespace-nowrap transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus',
    active
      ? 'bg-amber-100 text-amber-800 dark:bg-amber-900/30 dark:text-amber-300'
      : 'text-gray-600 hover:bg-gray-100 hover:text-gray-900 dark:text-stone-400 dark:hover:bg-stone-700 dark:hover:text-stone-100',
  ].join(' ')
}
</script>

<template>
  <!-- Event subheader: name, dates, and tab navigation -->
  <div class="border-line bg-surface border-b">
    <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
      <div
        class="flex flex-col py-3 sm:flex-row sm:items-center sm:justify-between"
      >
        <div class="min-w-0">
          <p class="text-ink-muted text-xs font-medium tracking-wide uppercase">
            Event
          </p>
          <router-link
            :to="`/events/${eventId}`"
            data-testid="event-name"
            class="text-ink focus-visible:outline-focus block truncate rounded text-lg font-semibold hover:text-amber-700 focus-visible:outline-2 focus-visible:outline-offset-2 dark:hover:text-amber-400"
          >
            {{ event.name }}
          </router-link>
          <p
            v-if="eventHasDates(props.event)"
            data-testid="event-dates"
            class="text-ink-muted hidden items-center gap-1 text-xs sm:flex"
          >
            <CalendarDaysIcon class="size-3.5" />
            <DateRangeDisplay
              :start-date="event.startDate!"
              :end-date="event.endDate!"
            />
          </p>
        </div>
        <nav
          class="-mx-4 mt-1 flex items-center gap-1 overflow-x-auto px-4 sm:mx-0 sm:mt-0 sm:px-0"
        >
          <router-link
            :to="`/events/${eventId}/planning`"
            :class="tabClass(activeTab === 'planning')"
          >
            Planning
          </router-link>
          <router-link
            :to="`/events/${eventId}/rsvp`"
            :class="tabClass(activeTab === 'rsvp')"
          >
            RSVP
          </router-link>
          <router-link
            :to="`/events/${eventId}/expenses`"
            :class="tabClass(activeTab === 'expenses')"
          >
            Expenses
          </router-link>
          <router-link
            :to="`/events/${eventId}/chores`"
            :class="tabClass(activeTab === 'chores')"
          >
            Chores
          </router-link>
        </nav>
      </div>
    </div>
  </div>
</template>
