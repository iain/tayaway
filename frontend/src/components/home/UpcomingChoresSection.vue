<script setup lang="ts">
import { useRouter } from 'vue-router'
import {
  ChevronRightIcon,
  ClipboardDocumentListIcon,
  ClockIcon,
} from '@heroicons/vue/24/outline'
import type { UpcomingChoreItem } from '@/composables/useUpcomingChores'
import BaseCard from '@/components/common/BaseCard.vue'
import SectionHeading from '@/components/common/SectionHeading.vue'
import WallClockTime from '@/components/common/WallClockTime.vue'

defineProps<{
  chores: UpcomingChoreItem[]
  hiddenCount: number
}>()

const router = useRouter()

function navigateToRoster(eventId: string): void {
  router.push(`/events/${eventId}/chores`)
}

function dayLabel(item: UpcomingChoreItem): string {
  return item.day === 'today' ? 'Today' : 'Tomorrow'
}
</script>

<template>
  <section data-testid="upcoming-chores-section">
    <SectionHeading :icon="ClipboardDocumentListIcon" title="Your chores" />

    <ul class="space-y-3">
      <BaseCard
        v-for="item in chores"
        :key="item.assignmentId"
        as="li"
        class="overflow-hidden"
      >
        <div
          class="flex cursor-pointer items-center gap-3 px-4 py-4 transition-all active:scale-[0.99] active:brightness-95 sm:px-6 dark:active:brightness-110"
          role="button"
          tabindex="0"
          @click="navigateToRoster(item.eventId)"
          @keydown.enter="navigateToRoster(item.eventId)"
          @keydown.space.prevent="navigateToRoster(item.eventId)"
        >
          <div class="min-w-0 flex-1">
            <h3 class="text-ink truncate text-base font-semibold">
              {{ item.choreName
              }}<span
                v-if="item.guestName"
                class="text-ink-muted text-sm font-normal"
              >
                · for {{ item.guestName }}</span
              >
            </h3>
            <div
              class="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm"
            >
              <span class="text-ink-muted inline-flex items-center gap-1">
                <ClockIcon class="size-4 text-amber-600 dark:text-amber-400" />
                {{ dayLabel(item) }} ·
                <WallClockTime
                  :date="item.date"
                  :time="item.time"
                  :zone="item.timezone"
                />
              </span>
              <span class="text-ink-muted truncate">{{ item.eventName }}</span>
            </div>
            <p v-if="item.note" class="text-ink-muted mt-1 truncate text-sm">
              {{ item.note }}
            </p>
          </div>
          <ChevronRightIcon
            class="text-ink-muted size-5 shrink-0"
            aria-hidden="true"
          />
        </div>
      </BaseCard>
    </ul>

    <p v-if="hiddenCount > 0" class="text-ink-muted mt-3 text-sm">
      +{{ hiddenCount }} more
    </p>
  </section>
</template>
