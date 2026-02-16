<script setup lang="ts">
import { useRouter } from 'vue-router'
import {
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

const router = useRouter()
const { pollsNeedingAttention } = usePollsNeedingAttention()

function navigateToEvent(eventId: string): void {
  router.push(`/events/${eventId}/vote`)
}
</script>

<template>
  <div>
    <header class="mb-6">
      <h1
        data-testid="page-title"
        class="text-3xl font-bold tracking-tight text-gray-900 dark:text-white"
      >
        Dashboard
      </h1>
    </header>

    <section>
      <h2 class="mb-4 text-lg font-medium text-gray-900 dark:text-white">
        Polls awaiting your vote
      </h2>

      <div v-if="pollsNeedingAttention.length === 0" class="py-12 text-center">
        <CheckCircleIcon
          class="mx-auto size-12 text-green-400 dark:text-green-500"
        />
        <h3 class="mt-2 text-sm font-semibold text-gray-900 dark:text-white">
          You're all caught up
        </h3>
        <p class="mt-1 text-sm text-gray-500 dark:text-stone-400">
          No polls need your vote right now.
        </p>
      </div>

      <ul v-else class="space-y-3">
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
                    Voted on {{ item.votedCount }} of {{ item.totalCount }} date
                    {{ item.totalCount === 1 ? 'option' : 'options' }}
                  </span>
                </div>
              </div>
            </div>
          </div>
        </li>
      </ul>
    </section>
  </div>
</template>
