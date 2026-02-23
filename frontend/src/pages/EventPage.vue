<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { CalendarDaysIcon } from '@heroicons/vue/24/outline'
import { useHydratedEvent } from '@/composables/useHydratedEvent'
import { eventHasDates } from '@/utils/event'
import DateRangeDisplay from '@/components/common/DateRangeDisplay.vue'

const route = useRoute()
const eventId = computed(() => route.params.id as string)
const { event } = useHydratedEvent(eventId)
</script>

<template>
  <div v-if="!event" class="text-gray-500 dark:text-stone-400">
    Event not found
  </div>

  <div v-else>
    <h1 class="text-4xl font-bold tracking-tight text-gray-900 dark:text-white">
      {{ event.name }}
    </h1>

    <p
      v-if="event.description"
      class="mt-3 text-xl text-gray-600 dark:text-stone-300"
    >
      {{ event.description }}
    </p>

    <div
      v-if="eventHasDates(event)"
      class="mt-4 flex items-center gap-2 text-gray-500 dark:text-stone-400"
    >
      <CalendarDaysIcon class="size-5" />
      <DateRangeDisplay
        :start-date="event.startDate!"
        :end-date="event.endDate!"
      />
    </div>
  </div>
</template>
