<script setup lang="ts">
import { ClipboardDocumentListIcon } from '@heroicons/vue/24/outline'
import AppButton from '@/components/common/AppButton.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import PageHeader from '@/components/common/PageHeader.vue'
import ChoreRosterSection from '@/components/chores/ChoreRosterSection.vue'
import { useFocusedEvent } from '@/composables/useFocusedEvent'
import { formatDateRange } from '@/utils/date'

// The roster shown is the focused event's — the same event the subheader
// names and the same one every other workspace page is about. Previously this
// page guessed one privately, which is why it agreed with the rest of the app
// only by coincidence.
const { focusedEvent } = useFocusedEvent()

// The dates say which days the grid covers.
function dateRange(event: {
  startDate: string | null
  endDate: string | null
}) {
  if (!event.startDate || !event.endDate) return undefined
  return formatDateRange(event.startDate, event.endDate)
}
</script>

<template>
  <div>
    <PageHeader title="Chores" :icon="ClipboardDocumentListIcon" />

    <ChoreRosterSection
      v-if="focusedEvent"
      :key="focusedEvent.id"
      :event-id="focusedEvent.id"
      :title="focusedEvent.name"
      :subtitle="dateRange(focusedEvent)"
      heading-style="section"
      :scroll-to-today="true"
    />

    <EmptyState
      v-else
      :icon="ClipboardDocumentListIcon"
      :heading-level="2"
      heading="No active event"
      description="Chores show up here once an event is under way or coming up."
    >
      <AppButton to="/events">View events</AppButton>
    </EmptyState>
  </div>
</template>
