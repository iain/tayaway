<script setup lang="ts">
import { useRouter } from 'vue-router'
import { CalendarDaysIcon, ChevronRightIcon } from '@heroicons/vue/24/outline'
import {
  formatEventDateRange,
  type RsvpEventItem,
} from '@/composables/useEventsNeedingRsvp'
import BaseCard from '@/components/common/BaseCard.vue'

defineProps<{
  events: RsvpEventItem[]
  addTopMargin: boolean
}>()

const router = useRouter()

function navigateToEventPage(eventId: string): void {
  router.push(`/events/${eventId}`)
}
</script>

<template>
  <section :class="addTopMargin ? 'mt-8' : ''">
    <h2 class="mb-4 text-lg font-medium text-gray-900 dark:text-white">
      Events awaiting your RSVP
    </h2>

    <ul class="space-y-3">
      <BaseCard
        v-for="item in events"
        :key="item.eventId"
        as="li"
        interactive
        class="overflow-hidden"
        @click="navigateToEventPage(item.eventId)"
      >
        <div class="px-4 py-4 sm:px-6">
          <div class="flex items-center gap-3">
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
                  <CalendarDaysIcon
                    class="size-4 text-amber-600 dark:text-amber-400"
                  />
                  {{ formatEventDateRange(item.startDate, item.endDate) }}
                </span>
              </div>
            </div>
            <ChevronRightIcon
              class="size-5 shrink-0 text-gray-400 dark:text-stone-500"
              aria-hidden="true"
            />
          </div>
        </div>
      </BaseCard>
    </ul>
  </section>
</template>
