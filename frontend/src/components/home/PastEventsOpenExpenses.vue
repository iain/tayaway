<script setup lang="ts">
import { useRouter } from 'vue-router'
import {
  BanknotesIcon,
  CalendarDaysIcon,
  ChevronRightIcon,
  ClockIcon,
} from '@heroicons/vue/24/outline'
import BaseCard from '@/components/common/BaseCard.vue'
import DateRangeDisplay from '@/components/common/DateRangeDisplay.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'
import type { PoolEvent } from '@/types/pool'

defineProps<{
  events: PoolEvent[]
  unsettledExpenseCountByEvent: Map<string, number>
  unpaidTransferCountByEvent: Map<string, number>
}>()

const router = useRouter()

function navigateToEventPage(eventId: string): void {
  router.push(`/events/${eventId}`)
}
</script>

<template>
  <section>
    <SectionHeading :icon="ClockIcon" title="Past events with open expenses" />

    <ul class="space-y-3">
      <BaseCard
        v-for="event in events"
        :key="event.id"
        as="li"
        class="overflow-hidden"
      >
        <div class="px-4 py-4 sm:px-6">
          <div
            class="flex cursor-pointer items-center gap-3 transition-all active:scale-[0.99] active:brightness-95 dark:active:brightness-110"
            role="button"
            tabindex="0"
            @click="navigateToEventPage(event.id)"
            @keydown.enter="navigateToEventPage(event.id)"
            @keydown.space.prevent="navigateToEventPage(event.id)"
          >
            <div class="min-w-0 flex-1">
              <h3
                class="truncate text-base font-semibold text-ink"
              >
                {{ event.name }}
              </h3>
              <div class="mt-1 flex flex-wrap items-center gap-3 text-sm">
                <span
                  class="text-ink-muted inline-flex items-center gap-1"
                >
                  <CalendarDaysIcon
                    class="size-4 text-amber-600 dark:text-amber-400"
                  />
                  <DateRangeDisplay
                    :start-date="event.startDate!"
                    :end-date="event.endDate!"
                  />
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
              v-if="(unsettledExpenseCountByEvent.get(event.id) ?? 0) > 0"
              :to="`/events/${event.id}/expenses`"
              class="inline-flex items-center gap-1.5 rounded-full bg-btn-secondary-fill text-btn-secondary-ink px-3 py-1 text-sm font-medium transition-colors hover:bg-rose-100 hover:text-rose-700 dark:hover:bg-rose-900/30 dark:hover:text-rose-300"
            >
              <BanknotesIcon class="size-4" />
              {{ unsettledExpenseCountByEvent.get(event.id) ?? 0 }} unsettled
            </router-link>
            <router-link
              v-if="(unpaidTransferCountByEvent.get(event.id) ?? 0) > 0"
              :to="`/events/${event.id}/expenses`"
              class="inline-flex items-center gap-1.5 rounded-full bg-btn-secondary-fill text-btn-secondary-ink px-3 py-1 text-sm font-medium transition-colors hover:bg-rose-100 hover:text-rose-700 dark:hover:bg-rose-900/30 dark:hover:text-rose-300"
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
