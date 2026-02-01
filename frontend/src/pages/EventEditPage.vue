<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import EventForm, { type EventFormData } from '@/components/events/EventForm.vue'
import { useEvents } from '@/composables/useEvents'
import type { Event } from '@/types'

const router = useRouter()
const route = useRoute()
const { fetchEvent, updateEvent, loading, error } = useEvents()

const event = ref<Event | null>(null)
const formError = ref<string | null>(null)
const initialLoading = ref(true)
const initialData = ref<EventFormData | undefined>(undefined)

const eventId = route.params.id as string

onMounted(async () => {
  try {
    const e = await fetchEvent(eventId)
    event.value = e
    initialData.value = {
      name: e.name,
      description: e.description || '',
      date_ranges: e.date_ranges.map(r => ({
        start_date: r.start_date,
        end_date: r.end_date,
      })),
    }
  } catch {
    formError.value = 'Failed to load event'
  } finally {
    initialLoading.value = false
  }
})

async function handleSubmit(data: EventFormData): Promise<void> {
  formError.value = null
  try {
    await updateEvent(eventId, {
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
      <h1 class="text-3xl font-bold tracking-tight text-gray-900 dark:text-white">
        Edit Event
      </h1>
    </header>

    <div class="bg-white dark:bg-gray-800 shadow rounded-lg">
      <div class="px-4 py-5 sm:p-6">
        <div
          v-if="initialLoading"
          class="text-gray-500 dark:text-gray-400"
        >
          Loading event...
        </div>

        <div
          v-else-if="formError && !event"
          class="text-red-600 dark:text-red-400"
        >
          {{ formError }}
        </div>

        <template v-else>
          <div
            v-if="formError"
            class="mb-4 text-red-600 dark:text-red-400"
          >
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
