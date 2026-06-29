<script setup lang="ts">
import { useRouter } from 'vue-router'
import {
  CalendarDaysIcon,
  ChevronRightIcon,
  UserGroupIcon,
} from '@heroicons/vue/24/outline'
import {
  formatEventDateRange,
  type UpcomingEventItem,
} from '@/composables/useUpcomingEvents'
import BaseCard from '@/components/common/BaseCard.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'

defineProps<{
  events: UpcomingEventItem[]
}>()

const router = useRouter()

function navigateToEventPage(eventId: string): void {
  router.push(`/events/${eventId}`)
}
</script>

<template>
  <section data-testid="upcoming-events-section">
    <SectionHeading :icon="CalendarDaysIcon" title="Upcoming events" />

    <ul class="space-y-3">
      <BaseCard
        v-for="item in events"
        :key="item.eventId"
        as="li"
        class="overflow-hidden"
      >
        <div class="px-4 py-4 sm:px-6">
          <div
            class="flex cursor-pointer items-center gap-3 transition-all active:scale-[0.99] active:brightness-95 dark:active:brightness-110"
            role="button"
            tabindex="0"
            @click="navigateToEventPage(item.eventId)"
            @keydown.enter="navigateToEventPage(item.eventId)"
            @keydown.space.prevent="navigateToEventPage(item.eventId)"
          >
            <div class="min-w-0 flex-1">
              <h3 class="text-ink truncate text-base font-semibold">
                {{ item.eventName }}
              </h3>
              <div class="mt-1 flex flex-wrap items-center gap-3 text-sm">
                <span class="text-ink-muted inline-flex items-center gap-1">
                  <CalendarDaysIcon
                    class="size-4 text-amber-600 dark:text-amber-400"
                  />
                  {{ formatEventDateRange(item.startDate, item.endDate) }}
                </span>
              </div>
            </div>
            <ChevronRightIcon
              class="text-ink-muted size-5 shrink-0"
              aria-hidden="true"
            />
          </div>
          <div class="mt-3 flex flex-wrap gap-2">
            <router-link
              v-if="item.needsRsvp"
              :to="`/events/${item.eventId}/planning`"
              class="inline-flex items-center gap-1.5 rounded-full bg-amber-100 px-3 py-1 text-sm font-medium text-amber-700 transition-colors hover:bg-amber-200 dark:bg-amber-900/30 dark:text-amber-300 dark:hover:bg-amber-900/50"
            >
              <UserGroupIcon class="size-4" />
              Needs your RSVP
            </router-link>
            <router-link
              v-else
              :to="`/events/${item.eventId}/planning`"
              class="bg-btn-secondary-fill text-btn-secondary-ink inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-sm font-medium transition-colors hover:bg-rose-100 hover:text-rose-700 dark:hover:bg-rose-900/30 dark:hover:text-rose-300"
            >
              <UserGroupIcon class="size-4" />
              {{ item.attendeeCount }} attending
            </router-link>
          </div>
        </div>
      </BaseCard>
    </ul>
  </section>
</template>
