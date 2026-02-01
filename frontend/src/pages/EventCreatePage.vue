<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import EventForm, { type EventFormData } from '@/components/events/EventForm.vue'
import { useEvents } from '@/composables/useEvents'

const router = useRouter()
const { createEvent, loading, error } = useEvents()
const formError = ref<string | null>(null)

async function handleSubmit(data: EventFormData): Promise<void> {
  formError.value = null
  try {
    await createEvent({
      name: data.name,
      description: data.description || undefined,
      date_ranges: data.date_ranges,
    })
    router.push('/events')
  } catch {
    formError.value = error.value || 'Failed to create event'
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
        Create Event
      </h1>
    </header>

    <div class="bg-white dark:bg-gray-800 shadow rounded-lg">
      <div class="px-4 py-5 sm:p-6">
        <div
          v-if="formError"
          class="mb-4 text-red-600 dark:text-red-400"
        >
          {{ formError }}
        </div>

        <EventForm
          submit-label="Create Event"
          :loading="loading"
          @submit="handleSubmit"
          @cancel="handleCancel"
        />
      </div>
    </div>
  </div>
</template>
