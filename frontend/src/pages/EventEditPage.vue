<script setup lang="ts">
import { ref, watch } from 'vue'
import { storeToRefs } from 'pinia'
import { useRouter, useRoute } from 'vue-router'
import EventForm, {
  type EventFormData,
} from '@/components/events/EventForm.vue'
import { useEventsStore, useWebSocketStore } from '@/stores'
import { useHydratedEvent } from '@/composables/useHydratedEvent'

const router = useRouter()
const route = useRoute()
const eventsStore = useEventsStore()
const wsStore = useWebSocketStore()
const { loading, error } = storeToRefs(eventsStore)
const { hasSynced } = storeToRefs(wsStore)

const formError = ref<string | null>(null)
const initialData = ref<EventFormData | undefined>(undefined)

const eventId = route.params.id as string

// Get event reactively from pool - benefits from optimistic updates
const { event } = useHydratedEvent(eventId)

// Populate initial form data when event is loaded
watch(
  event,
  (e) => {
    if (e && !initialData.value) {
      initialData.value = {
        name: e.name,
        description: e.description || '',
        date_ranges: e.dateRanges.map((r) => ({
          start_date: r.startDate,
          end_date: r.endDate,
        })),
      }
    }
  },
  { immediate: true }
)

async function handleSubmit(data: EventFormData): Promise<void> {
  formError.value = null
  try {
    await eventsStore.updateEvent(eventId, {
      name: data.name,
      description: data.description || undefined,
      date_ranges: data.date_ranges,
    })
    router.push('/events')
  } catch {
    formError.value = error.value || 'Failed to update event'
  }
}

function handleCancel(): void {
  router.push('/events')
}
</script>

<template>
  <div>
    <header class="mb-6">
      <h1
        class="text-3xl font-bold tracking-tight text-gray-900 dark:text-white"
      >
        Edit Event
      </h1>
    </header>

    <div class="rounded-lg bg-white shadow dark:bg-gray-800">
      <div class="px-4 py-5 sm:p-6">
        <div v-if="!hasSynced" class="text-gray-500 dark:text-gray-400">
          Loading...
        </div>

        <div v-else-if="!event" class="text-gray-500 dark:text-gray-400">
          Event not found
        </div>

        <template v-else>
          <div v-if="formError" class="mb-4 text-red-600 dark:text-red-400">
            {{ formError }}
          </div>

          <EventForm
            :initial-data="initialData"
            submit-label="Save Changes"
            :loading="loading"
            @submit="handleSubmit"
            @cancel="handleCancel"
          />
        </template>
      </div>
    </div>
  </div>
</template>
