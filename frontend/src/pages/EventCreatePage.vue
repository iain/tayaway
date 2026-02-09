<script setup lang="ts">
import { ref } from 'vue'
import { storeToRefs } from 'pinia'
import { useRouter } from 'vue-router'
import EventForm, {
  type EventFormData,
} from '@/components/events/EventForm.vue'
import { useEventsStore } from '@/stores'

const router = useRouter()
const eventsStore = useEventsStore()
const { loading, error } = storeToRefs(eventsStore)
const formError = ref<string | null>(null)

async function handleSubmit(data: EventFormData): Promise<void> {
  formError.value = null
  try {
    await eventsStore.createEvent({
      name: data.name,
      description: data.description || undefined,
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
      <h1
        class="text-3xl font-bold tracking-tight text-gray-900 dark:text-white"
      >
        Create Event
      </h1>
    </header>

    <div class="rounded-lg bg-white shadow dark:bg-gray-800">
      <div class="px-4 py-5 sm:p-6">
        <div v-if="formError" class="mb-4 text-red-600 dark:text-red-400">
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
