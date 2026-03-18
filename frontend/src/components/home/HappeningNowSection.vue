<script setup lang="ts">
import { useRouter } from 'vue-router'
import {
  BanknotesIcon,
  CalendarDaysIcon,
  UserGroupIcon,
} from '@heroicons/vue/24/outline'
import BaseCard from '@/components/common/BaseCard.vue'
import DateRangeDisplay from '@/components/common/DateRangeDisplay.vue'
import type { PoolEvent } from '@/types/pool'

defineProps<{
  events: PoolEvent[]
  attendeeCountByEvent: Map<string, number>
  unpaidTransferCountByEvent: Map<string, number>
  addTopMargin: boolean
}>()

const router = useRouter()

function navigateToEventPage(eventId: string): void {
  router.push(`/events/${eventId}`)
}
</script>

<template>
  <section
    data-testid="happening-now-section"
    :class="addTopMargin ? 'mt-8' : ''"
  >
    <h2 class="mb-4 text-lg font-medium text-gray-900 dark:text-white">
      Happening now
    </h2>

    <ul class="space-y-3">
      <BaseCard
        v-for="event in events"
        :key="event.id"
        as="li"
        class="overflow-hidden"
      >
        <div class="px-4 py-4 sm:px-6">
          <div
            class="cursor-pointer"
            role="button"
            tabindex="0"
            @click="navigateToEventPage(event.id)"
            @keydown.enter="navigateToEventPage(event.id)"
            @keydown.space.prevent="navigateToEventPage(event.id)"
          >
            <h3
              class="truncate text-base font-semibold text-gray-900 dark:text-white"
            >
              {{ event.name }}
            </h3>
            <div class="mt-1 flex flex-wrap items-center gap-3 text-sm">
              <span
                class="inline-flex items-center gap-1 text-gray-500 dark:text-stone-400"
              >
                <CalendarDaysIcon class="size-4" />
                <DateRangeDisplay
                  :start-date="event.startDate!"
                  :end-date="event.endDate!"
                />
              </span>
            </div>
          </div>
          <div class="mt-3 flex flex-wrap gap-2">
            <router-link
              :to="`/events/${event.id}/rsvp`"
              class="inline-flex items-center gap-1.5 rounded-full bg-gray-100 px-3 py-1 text-sm font-medium text-gray-700 transition-colors hover:bg-rose-100 hover:text-rose-700 dark:bg-stone-700 dark:text-stone-300 dark:hover:bg-rose-900/30 dark:hover:text-rose-300"
            >
              <UserGroupIcon class="size-4" />
              {{ attendeeCountByEvent.get(event.id) ?? 0 }} attending
            </router-link>
            <router-link
              v-if="(unpaidTransferCountByEvent.get(event.id) ?? 0) > 0"
              :to="`/events/${event.id}/expenses`"
              class="inline-flex items-center gap-1.5 rounded-full bg-gray-100 px-3 py-1 text-sm font-medium text-gray-700 transition-colors hover:bg-rose-100 hover:text-rose-700 dark:bg-stone-700 dark:text-stone-300 dark:hover:bg-rose-900/30 dark:hover:text-rose-300"
            >
              <BanknotesIcon class="size-4" />
              {{ unpaidTransferCountByEvent.get(event.id) ?? 0 }} unpaid
            </router-link>
          </div>
        </div>
      </BaseCard>
    </ul>
  </section>
</template>
