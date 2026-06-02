<script setup lang="ts">
import { useRouter } from 'vue-router'
import {
  CalendarDaysIcon,
  ChevronRightIcon,
  UserGroupIcon,
} from '@heroicons/vue/24/outline'
import {
  formatEventDateRange,
  type RsvpEventItem,
} from '@/composables/useEventsNeedingRsvp'
import BaseCard from '@/components/common/BaseCard.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'

defineProps<{
  events: RsvpEventItem[]
}>()

const router = useRouter()

function navigateToEventPage(eventId: string): void {
  router.push(`/events/${eventId}`)
}
</script>

<template>
  <section>
    <SectionHeading :icon="UserGroupIcon" title="Events awaiting your RSVP" />

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
        </div>
      </BaseCard>
    </ul>
  </section>
</template>
