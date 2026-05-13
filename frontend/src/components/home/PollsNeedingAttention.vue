<script setup lang="ts">
import { useRouter } from 'vue-router'
import {
  ChevronRightIcon,
  ClockIcon,
  HandRaisedIcon,
  InboxIcon,
} from '@heroicons/vue/24/outline'
import {
  formatDeadline,
  isUrgent,
  isPastDeadline,
  type PollItem,
} from '@/composables/usePollsNeedingAttention'
import BaseCard from '@/components/common/BaseCard.vue'
import AppBadge from '@/components/common/AppBadge.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'

defineProps<{
  polls: PollItem[]
}>()

const router = useRouter()

function navigateToEvent(eventId: string): void {
  router.push(`/events/${eventId}/planning/vote`)
}
</script>

<template>
  <section>
    <SectionHeading :icon="HandRaisedIcon" title="Polls awaiting your vote" />

    <ul class="space-y-3">
      <BaseCard
        v-for="item in polls"
        :key="item.eventId"
        as="li"
        interactive
        :variant="
          isPastDeadline(item.deadline)
            ? 'urgent'
            : isUrgent(item.deadline)
              ? 'action'
              : undefined
        "
        class="overflow-hidden"
        @click="navigateToEvent(item.eventId)"
      >
        <div class="px-4 py-4 sm:px-6">
          <div class="flex items-center justify-between gap-3">
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
                      ? 'font-semibold text-red-600 dark:text-red-400'
                      : isUrgent(item.deadline)
                        ? 'font-medium text-amber-600 dark:text-amber-400'
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
                  Voted on {{ item.votedCount }} of {{ item.totalCount }} date
                  {{ item.totalCount === 1 ? 'option' : 'options' }}
                </span>
              </div>
            </div>
            <div class="flex shrink-0 items-center gap-2">
              <AppBadge
                v-if="isPastDeadline(item.deadline)"
                variant="danger"
                size="sm"
              >
                Overdue
              </AppBadge>
              <ChevronRightIcon
                class="size-5 text-gray-400 dark:text-stone-500"
                aria-hidden="true"
              />
            </div>
          </div>
        </div>
      </BaseCard>
    </ul>
  </section>
</template>
