<script setup lang="ts">
import { computed } from 'vue'
import { useRouter } from 'vue-router'
import {
  CalendarDaysIcon,
  CheckCircleIcon,
  ClockIcon,
  InboxIcon,
} from '@heroicons/vue/24/outline'
import {
  usePollsNeedingAttention,
  formatDeadline,
  isUrgent,
  isPastDeadline,
} from '@/composables/usePollsNeedingAttention'
import {
  useEventsNeedingRsvp,
  formatEventDateRange,
} from '@/composables/useEventsNeedingRsvp'
import PageHeader from '@/components/common/PageHeader.vue'
import EmptyState from '@/components/common/EmptyState.vue'

const router = useRouter()
const { pollsNeedingAttention } = usePollsNeedingAttention()
const { eventsNeedingRsvp } = useEventsNeedingRsvp()

const allCaughtUp = computed(
  () =>
    pollsNeedingAttention.value.length === 0 &&
    eventsNeedingRsvp.value.length === 0
)

function navigateToEvent(eventId: string): void {
  router.push(`/events/${eventId}/planning/vote`)
}

function navigateToEventPage(eventId: string): void {
  router.push(`/events/${eventId}`)
}
</script>

<template>
  <div>
    <PageHeader title="Dashboard" data-testid="page-title" />

    <EmptyState
      v-if="allCaughtUp"
      :icon="CheckCircleIcon"
      heading="You're all caught up"
      description="Nothing needs your attention right now."
      icon-class="text-green-400 dark:text-green-500"
    />

    <template v-else>
      <section v-if="pollsNeedingAttention.length > 0">
        <h2 class="mb-4 text-lg font-medium text-gray-900 dark:text-white">
          Polls awaiting your vote
        </h2>

        <ul class="space-y-3">
          <li
            v-for="item in pollsNeedingAttention"
            :key="item.eventId"
            class="cursor-pointer overflow-hidden rounded-lg bg-white shadow transition-all hover:ring-2 hover:ring-rose-500 dark:bg-stone-800"
            @click="navigateToEvent(item.eventId)"
          >
            <div class="px-4 py-4 sm:px-6">
              <div class="flex items-center justify-between">
                <div class="min-w-0 flex-1">
                  <h3
                    class="truncate text-base font-semibold text-gray-900 dark:text-white"
                  >
                    {{ item.eventName }}
                  </h3>
                  <div class="mt-1 flex flex-wrap items-center gap-3 text-sm">
                    <span
                      class="inline-flex items-center gap-1"
                      :class="
                        isPastDeadline(item.deadline)
                          ? 'text-red-600 dark:text-red-400'
                          : isUrgent(item.deadline)
                            ? 'text-amber-600 dark:text-amber-400'
                            : 'text-gray-500 dark:text-stone-400'
                      "
                    >
                      <ClockIcon class="size-4" />
                      {{ formatDeadline(item.deadline) }}
                    </span>
                    <span
                      class="inline-flex items-center gap-1 text-gray-500 dark:text-stone-400"
                    >
                      <InboxIcon class="size-4" />
                      Voted on {{ item.votedCount }} of
                      {{ item.totalCount }} date
                      {{ item.totalCount === 1 ? 'option' : 'options' }}
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </li>
        </ul>
      </section>

      <section
        v-if="eventsNeedingRsvp.length > 0"
        :class="pollsNeedingAttention.length > 0 ? 'mt-8' : ''"
      >
        <h2 class="mb-4 text-lg font-medium text-gray-900 dark:text-white">
          Events awaiting your RSVP
        </h2>

        <ul class="space-y-3">
          <li
            v-for="item in eventsNeedingRsvp"
            :key="item.eventId"
            class="cursor-pointer overflow-hidden rounded-lg bg-white shadow transition-all hover:ring-2 hover:ring-rose-500 dark:bg-stone-800"
            @click="navigateToEventPage(item.eventId)"
          >
            <div class="px-4 py-4 sm:px-6">
              <div class="flex items-center justify-between">
                <div class="min-w-0 flex-1">
                  <h3
                    class="truncate text-base font-semibold text-gray-900 dark:text-white"
                  >
                    {{ item.eventName }}
                  </h3>
                  <div class="mt-1 flex flex-wrap items-center gap-3 text-sm">
                    <span
                      class="inline-flex items-center gap-1 text-gray-500 dark:text-stone-400"
                    >
                      <CalendarDaysIcon class="size-4" />
                      {{ formatEventDateRange(item.startDate, item.endDate) }}
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </li>
        </ul>
      </section>
    </template>
  </div>
</template>
