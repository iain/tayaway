<script setup lang="ts">
import { ref } from 'vue'
import { storeToRefs } from 'pinia'
import { useRouter } from 'vue-router'
import EventForm, {
  type EventFormData,
} from '@/components/events/EventForm.vue'
import { useEventsStore, useNotificationsStore } from '@/stores'
import PageHeader from '@/components/common/PageHeader.vue'
import BaseCard from '@/components/common/BaseCard.vue'

const router = useRouter()
const eventsStore = useEventsStore()
const { loading, error } = storeToRefs(eventsStore)
const formError = ref<string | null>(null)

async function handleSubmit(data: EventFormData): Promise<void> {
  formError.value = null
  try {
    const { queued } = await eventsStore.createEvent({
      name: data.name,
      description: data.description || undefined,
      startDate: data.startDate || undefined,
      endDate: data.endDate || undefined,
      locationName: data.locationName || undefined,
      latitude: data.latitude ?? undefined,
      longitude: data.longitude ?? undefined,
    })
    if (queued) {
      const notifications = useNotificationsStore()
      notifications.showInfo('Event will be created when back online')
    }
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
    <PageHeader title="Create Event" />

    <BaseCard>
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
    </BaseCard>
  </div>
</template>
